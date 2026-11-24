using Godot;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

using Baugenossen.Vision;

/// <summary>
/// Capture the webcam and follow the builder's body pose on a background thread.
/// </summary>
/// <remarks>
/// <para>
/// Taken over from Drunken Vikings, without the rowing, the hands and the
/// recording, but with the hand detector (YOLOX) for the hand cursor of the
/// screens. The pose thread runs <see cref="PoseFollower"/> back to back:
/// RTMPose-t follows the builder on every frame, and RTMO finds them at the
/// start or when they were lost. The main thread only copies a camera frame
/// when the thread asks for one, so that we never queue frames (and latency)
/// nor copy frames nobody processes. The thread publishes immutable snapshots
/// (<see cref="VisionSnapshot"/>).
/// </para>
/// <para>
/// The camera starts only when the game asks for it (<see cref="StartCamera"/>),
/// after the player agreed to use it; it never starts on its own. The camera
/// frames stay in memory and are never saved nor sent anywhere.
/// </para>
/// <para>
/// The game (GDScript, scenes/input/vision_pose_provider.gd) uses only the plain
/// getters: <see cref="GetKeypoints"/>, <see cref="GetKeypointScores"/>,
/// <see cref="GetPoseTimestamp"/> and <see cref="GetPictureSize"/>.
/// </para>
/// </remarks>
public partial class VisionService : Node
{
    public enum ServiceStatus
    {
        Disabled,
        SearchingCamera,
        LoadingModels,
        Running,
        NoCamera,
        ModelsMissing,
        Failed,
    }

    public const string RtmoModelPath = "res://scenes/vision/rtmo/model/rtmo_t_body7_416x416.onnx";

    public const string RtmPoseModelPath = "res://scenes/vision/rtmpose/model/rtmpose_t_body7_256x192.onnx";

    public const string HandModelPath = "res://scenes/vision/yolox/model/yolox_n_body_head_hand_Nx3xHxW.onnx";

    /// <summary>How long to wait for the camera feeds to appear, in seconds.</summary>
    private const double _cameraSearchTimeout = 5.0;

    /// <summary>Once a feed appeared, how long to wait for more, in seconds.</summary>
    private const double _graceAfterFirstFeed = 1.0;

    /// <summary>Set to false to forbid the camera, e.g., in the tests (<c>--no-camera</c>).</summary>
    [Export]
    public bool CameraAllowed = true;

    /// <summary>Which of the compatible cameras to use.</summary>
    [Export]
    public int CameraIndex = 0;

    /// <summary>The threads of RTMO.</summary>
    [Export]
    public int Threads = 2;

    public ServiceStatus Status { get; private set; } = ServiceStatus.Disabled;

    public string StatusMessage { get; private set; } = "";

    public CameraTexture? CameraTexture { get; private set; }

    private readonly Stopwatch _clock = Stopwatch.StartNew();

    /// <summary>Seconds on the clock of the frame timestamps.</summary>
    public double Now => _clock.Elapsed.TotalSeconds;

    private VisionSnapshot? _latest;

    /// <summary>The latest poses, or null before the first ones.</summary>
    public VisionSnapshot? Latest => Volatile.Read(ref _latest);

    private CameraFeed? _feed;

    /// <summary>The camera extension on Windows (see <see cref="StartCameraExtension"/>), or null.</summary>
    private GodotObject? _cameraExtension;

    /// <summary>
    /// Why there may be no camera: "unsupported" (on Windows without the camera
    /// extension), "denied" (Windows does not allow the camera), or "" otherwise.
    /// </summary>
    private string _noCameraReason = "";

    /// <summary>
    /// The chroma plane of a feed which delivers its frames as two planes (Y and
    /// CbCr, e.g., on macOS); <see cref="CameraTexture"/> then holds the Y plane.
    /// </summary>
    private CameraTexture? _cbcrTexture;

    /// <summary>The frames of a two-plane feed converted to RGB, for the preview.</summary>
    private ImageTexture? _ycbcrPreview;

    /// <summary>Try to activate the feed again at this time, see <see cref="RetryActivation"/>.</summary>
    private double _nextActivationAttempt = double.NaN;

    /// <summary>Try to activate an inactive feed again every this many seconds.</summary>
    private const double _activationRetryPeriod = 3.0;

    /// <summary>Convert the two-plane frames down to at most this width.</summary>
    private const int _maxYcbcrWidth = 640;

    private double _searchStarted = double.NaN;
    private double _firstFeedAt = double.NaN;

    /// <summary>Whether we kept the full frame rate of the camera once it streamed.</summary>
    private bool _fullFrameRateKept;

    /// <summary>Hand the camera frames over to the pose thread.</summary>
    private sealed class FrameSlot
    {
        public volatile bool Requested;
        public readonly AutoResetEvent Ready = new(false);
        private readonly object _lock = new();
        private Frame? _pending;

        public void Put(Frame frame)
        {
            lock (_lock)
            {
                _pending = frame;
            }

            Requested = false;
            Ready.Set();
        }

        public Frame? Take()
        {
            lock (_lock)
            {
                var frame = _pending;
                _pending = null;
                return frame;
            }
        }
    }

    private Thread? _poseThread;
    private Thread? _handThread;
    private volatile bool _running;

    /// <summary>Whether a screen shows the hand cursor and needs the hands.</summary>
    private volatile bool _handTracking;

    private readonly FrameSlot _handSlot = new();

    /// <summary>The hands which YOLOX found last: the time, the size of the frame and the boxes.</summary>
    private sealed class HandSnapshot
    {
        public double Timestamp { get; init; }
        public int Width { get; init; }
        public int Height { get; init; }
        public IReadOnlyList<BoundingBox> Hands { get; init; } = Array.Empty<BoundingBox>();
    }

    private HandSnapshot? _latestHands;

    /// <summary>Whether we shut down (see <see cref="Shutdown"/>): no more frames are taken.</summary>
    private bool _shutDown;
    private readonly FrameSlot _poseSlot = new();

    /// <summary>
    /// Start looking for the camera and, once found, follow the builder; call it
    /// only after the player agreed to use the camera. Calling it again while
    /// the camera runs does nothing. Return whether the search started.
    /// </summary>
    public bool StartCamera()
    {
        if (!CameraAllowed)
        {
            SetStatus(ServiceStatus.Disabled, "The camera is switched off.");
            return false;
        }

        if (Status is ServiceStatus.SearchingCamera or ServiceStatus.LoadingModels or ServiceStatus.Running)
        {
            return true;
        }

        foreach (string path in new[] { RtmoModelPath, RtmPoseModelPath })
        {
            if (!FileAccess.FileExists(path))
            {
                SetStatus(ServiceStatus.ModelsMissing, $"The pose model {path} is missing; run `git lfs pull`.");
                return false;
            }
        }

        _shutDown = false;
        CameraServer.MonitoringFeeds = true;
        if (OS.GetName() == "Windows" && _cameraExtension == null)
        {
            StartCameraExtension();
        }

        _searchStarted = Now;
        _firstFeedAt = double.NaN;
        SetStatus(ServiceStatus.SearchingCamera, "Looking for a camera...");
        return true;
    }

    /// <summary>Stop the camera and the pose thread; the game may start them again later.</summary>
    public void StopCamera()
    {
        Shutdown();
        _shutDown = false;
        Volatile.Write(ref _latest, null);
        SetStatus(ServiceStatus.Disabled, "The camera is switched off.");
    }

    public override void _Process(double delta)
    {
        double now = Now;

        if (Status == ServiceStatus.SearchingCamera)
        {
            SearchCamera(now);
        }

        RetryActivation(now);
    }

    // ---------------------------------------------------------------------
    // The getters for GDScript
    // ---------------------------------------------------------------------

    public string GetStatus() => Status.ToString();

    public string GetStatusMessage() => StatusMessage;

    public bool IsRunning() => Status == ServiceStatus.Running;

    /// <summary>"unsupported", "denied" or "" (see <see cref="_noCameraReason"/>).</summary>
    public string GetNoCameraReason() => _noCameraReason;

    public Texture2D? GetCameraTexture() => _ycbcrPreview ?? (Texture2D?)CameraTexture;

    /// <summary>The size of the camera picture in pixels, or zero before the first pose.</summary>
    public Vector2 GetPictureSize()
    {
        var snapshot = Latest;
        return snapshot == null ? Vector2.Zero : new Vector2(snapshot.Width, snapshot.Height);
    }

    /// <summary>The time of the latest pose on the clock <see cref="Now"/>, or -1 without one.</summary>
    public double GetPoseTimestamp()
    {
        var snapshot = Latest;
        return snapshot == null || snapshot.Players.Count == 0 || snapshot.Players[0] == null
            ? -1.0
            : snapshot.Timestamp;
    }

    /// <summary>The current time on the clock of <see cref="GetPoseTimestamp"/>.</summary>
    public double GetNow() => Now;

    private Pose? PoseOfBuilder()
    {
        var snapshot = Latest;
        return snapshot != null && snapshot.Players.Count > 0 ? snapshot.Players[0] : null;
    }

    /// <summary>
    /// The builder's 17 COCO key points in the <em>not mirrored</em> picture,
    /// normalized to [0, 1]; empty without them. The game mirrors them itself,
    /// as the settings say.
    /// </summary>
    public Vector2[] GetKeypoints()
    {
        var snapshot = Latest;
        var pose = PoseOfBuilder();
        if (snapshot == null || pose == null)
        {
            return Array.Empty<Vector2>();
        }

        var points = new Vector2[Pose.KeypointCount];
        for (int i = 0; i < Pose.KeypointCount; i++)
        {
            var keypoint = pose.Keypoints[i];
            points[i] = new Vector2(keypoint.X / snapshot.Width, keypoint.Y / snapshot.Height);
        }

        return points;
    }

    /// <summary>The scores of the key points of <see cref="GetKeypoints"/>.</summary>
    public float[] GetKeypointScores()
    {
        var pose = PoseOfBuilder();
        if (pose == null)
        {
            return Array.Empty<float>();
        }

        var scores = new float[Pose.KeypointCount];
        for (int i = 0; i < Pose.KeypointCount; i++)
        {
            scores[i] = pose.Keypoints[i].Score;
        }

        return scores;
    }

    /// <summary>
    /// Run the hand detector (for the hand cursor of the screens) or stop it,
    /// so that it takes the processor only while a screen needs it.
    /// </summary>
    public void SetHandTracking(bool on) => _handTracking = on;

    /// <summary>
    /// The centers of the hands which the detector found lately, in the
    /// <em>not mirrored</em> picture, normalized; empty if none were found in
    /// the last 0.3 s, or the detector does not run.
    /// </summary>
    public Vector2[] GetHands()
    {
        var snapshot = Volatile.Read(ref _latestHands);
        if (snapshot == null || !_handTracking || Now - snapshot.Timestamp > 0.3)
        {
            return Array.Empty<Vector2>();
        }

        var hands = new Vector2[snapshot.Hands.Count];
        for (int i = 0; i < hands.Length; i++)
        {
            var box = snapshot.Hands[i];
            hands[i] = new Vector2(box.CenterX / snapshot.Width, box.CenterY / snapshot.Height);
        }

        return hands;
    }

    /// <summary>How long the latest poses took, in milliseconds.</summary>
    public double GetInferenceMs() => Latest?.InferenceMs ?? 0.0;

    // ---------------------------------------------------------------------
    // The camera
    // ---------------------------------------------------------------------

    /// <summary>
    /// Load CameraServerExtension, which provides the camera feeds on Windows,
    /// where Godot 4.6 implements no camera (see
    /// addons/CameraServerExtension/CameraServerExtension.gdextension).
    /// </summary>
    /// <remarks>
    /// The extension must be created after <see cref="CameraServer.MonitoringFeeds"/>
    /// is set, and must live as long as its feeds are in use.
    /// </remarks>
    private void StartCameraExtension()
    {
        // NOTE (mristin):
        // The packaging puts the extension next to the executable; in the
        // editor, it stays in the project.
        string directory = OS.HasFeature("editor")
            ? ProjectSettings.GlobalizePath("res://addons/CameraServerExtension")
            : OS.GetExecutablePath().GetBaseDir();
        string path = directory.PathJoin("CameraServerExtension.gdextension");
        if (!System.IO.File.Exists(path))
        {
            GD.PushWarning($"The camera extension {path} is missing; there is no camera on Windows without it.");
            _noCameraReason = "unsupported";
            return;
        }

        var status = GDExtensionManager.LoadExtension(path);
        if (status != GDExtensionManager.LoadStatus.Ok && status != GDExtensionManager.LoadStatus.AlreadyLoaded)
        {
            GD.PushWarning($"The camera extension {path} did not load: {status}.");
            _noCameraReason = "unsupported";
            return;
        }

        if (!ClassDB.ClassExists("CameraServerExtension"))
        {
            GD.PushWarning($"The camera extension {path} loaded, but provides no CameraServerExtension.");
            _noCameraReason = "unsupported";
            return;
        }

        _cameraExtension = ClassDB.Instantiate("CameraServerExtension").AsGodotObject();
        GD.Print($"Loaded the camera extension {path}.");
        if (_cameraExtension != null && !_cameraExtension.Call("permission_granted").AsBool())
        {
            _noCameraReason = "denied";
        }
    }

    /// <summary>
    /// Whether a feed comes from CameraServerExtension, whose formats must be
    /// called by name: the methods of <see cref="CameraFeed"/> do not reach them.
    /// </summary>
    private static bool IsExtensionFeed(CameraFeed feed) => feed.GetClass() == "CameraFeedExtension";

    private static Godot.Collections.Array GetFormats(CameraFeed feed) =>
        IsExtensionFeed(feed) ? feed.Call("get_formats").AsGodotArray() : feed.GetFormats();

    private static void SetFormat(CameraFeed feed, int index)
    {
        var parameters = new Godot.Collections.Dictionary();
        if (IsExtensionFeed(feed))
        {
            feed.Call("set_format", index, parameters);
        }
        else
        {
            feed.SetFormat(index, parameters);
        }
    }

    private void SearchCamera(double now)
    {
        int count = CameraServer.GetFeedCount();
        if (count > 0 && double.IsNaN(_firstFeedAt))
        {
            _firstFeedAt = now;
        }

        bool timeout = now - _searchStarted > _cameraSearchTimeout;
        bool graceOver = !double.IsNaN(_firstFeedAt) && now - _firstFeedAt > _graceAfterFirstFeed;
        if (!timeout && !graceOver)
        {
            return;
        }

        var candidates = new List<(CameraFeed Feed, int Format)>();
        for (int i = 0; i < count; i++)
        {
            CameraFeed feed = CameraServer.GetFeed(i);
            int format = FindFormat(feed);
            if (format >= 0)
            {
                candidates.Add((feed, format));
            }
        }

        GD.Print($"The camera server reports {count} feed(s), {candidates.Count} compatible.");

        if (candidates.Count == 0)
        {
            SetStatus(
                ServiceStatus.NoCamera,
                _noCameraReason switch
                {
                    "unsupported" => "The camera does not work on Windows without the camera extension.",
                    "denied" => "Windows does not allow the camera (Settings, Privacy, Camera).",
                    _ => count == 0 ? "No camera found." : "No camera supports 640x480, which the vision needs.",
                }
            );
            return;
        }

        var (chosen, formatIndex) = candidates[Math.Clamp(CameraIndex, 0, candidates.Count - 1)];
        StartFeed(chosen, formatIndex);
    }

    /// <summary>
    /// Find the 640x480 format, preferring YUYV; return -1 if there is none, and
    /// <see cref="_anyFormat"/> if the feed lists no formats at all.
    /// </summary>
    /// <remarks>
    /// Godot lists the formats only on Linux; elsewhere (e.g., on macOS) the feed
    /// runs at the resolution of the system, which the pose letterboxes anyhow.
    /// </remarks>
    private static int FindFormat(CameraFeed feed)
    {
        var formats = GetFormats(feed);
        if (formats.Count == 0)
        {
            return _anyFormat;
        }

        int fallback = -1;
        for (int i = 0; i < formats.Count; i++)
        {
            var format = formats[i].AsGodotDictionary();
            int width = format.ContainsKey("width") ? format["width"].AsInt32() : 0;
            int height = format.ContainsKey("height") ? format["height"].AsInt32() : 0;
            string pixelFormat = format.ContainsKey("format") ? format["format"].AsString() : "";
            if (width != 640 || height != 480)
            {
                continue;
            }

            // NOTE (mristin):
            // V4L2 on Linux calls the format YUYV, Media Foundation on Windows YUY2.
            if (pixelFormat.StartsWith("YUYV") || pixelFormat.StartsWith("YUY2"))
            {
                return i;
            }

            fallback = fallback < 0 ? i : fallback;
        }

        return fallback;
    }

    /// <summary>The format index of a feed which lists no formats (see <see cref="FindFormat"/>).</summary>
    private const int _anyFormat = int.MaxValue;

    /// <summary>Keep the camera at its full frame rate in dim light, too (see <see cref="LinuxCameraControls"/>).</summary>
    private void KeepFullFrameRate()
    {
        if (_feed == null)
        {
            return;
        }

        // NOTE (mristin):
        // Only a nicety: whatever goes wrong, the camera runs as it would anyway.
        try
        {
            var devices = LinuxCameraControls.KeepFullFrameRate(_feed.GetName());
            if (devices.Count > 0)
            {
                GD.Print($"Switched off the dynamic frame rate of the camera on {string.Join(", ", devices)}.");
            }
        }
        catch (Exception exception)
        {
            GD.PushWarning($"Could not keep the full frame rate of the camera: {exception.Message}");
        }
    }

    private void StartFeed(CameraFeed feed, int formatIndex)
    {
        string description = formatIndex == _anyFormat
            ? $"{feed.GetName()}, the default format"
            : $"{feed.GetName()}, format #{formatIndex}: {GetFormats(feed)[formatIndex]}";
        GD.Print($"Starting the camera {description}");
        _feed = feed;
        if (formatIndex != _anyFormat)
        {
            SetFormat(_feed, formatIndex);
        }

        _feed.FeedIsActive = true;
        _nextActivationAttempt = Now + _activationRetryPeriod;
        KeepFullFrameRate();

        CameraTexture = new CameraTexture { CameraFeedId = _feed.GetId(), CameraIsActive = true };
        _cbcrTexture = new CameraTexture
        {
            CameraFeedId = _feed.GetId(),
            WhichFeed = CameraServer.FeedImage.CbcrImage,
            CameraIsActive = true,
        };
        _feed.FrameChanged += OnFrameChanged;

        SetStatus(ServiceStatus.LoadingModels, "Loading the models...");

        byte[] rtmo = FileAccess.GetFileAsBytes(RtmoModelPath);
        byte[] rtmPose = FileAccess.GetFileAsBytes(RtmPoseModelPath);
        int threads = Threads;
        _running = true;
        _poseThread = new Thread(() => PoseLoop(rtmo, rtmPose, threads))
        {
            IsBackground = true,
            Name = "Pose",
            Priority = ThreadPriority.BelowNormal,
        };
        _poseThread.Start();

        if (FileAccess.FileExists(HandModelPath))
        {
            byte[] handModel = FileAccess.GetFileAsBytes(HandModelPath);
            _handThread = new Thread(() => HandLoop(handModel))
            {
                IsBackground = true,
                Name = "Hands",
                Priority = ThreadPriority.BelowNormal,
            };
            _handThread.Start();
        }
        else
        {
            GD.PushWarning($"The hand model {HandModelPath} is missing; the screens work only with the mouse.");
        }
    }

    private void OnFrameChanged()
    {
        if (_shutDown)
        {
            return;
        }

        if (!_fullFrameRateKept)
        {
            // NOTE (mristin):
            // Once more with the first frame: a driver may reset the controls when
            // the camera starts to stream.
            _fullFrameRateKept = true;
            KeepFullFrameRate();
        }

        if (CameraTexture == null || _feed == null)
        {
            return;
        }

        bool forPose = _poseSlot.Requested;
        bool forHands = _handTracking && _handSlot.Requested;
        bool twoPlanes = _feed.GetDatatype() == CameraFeed.FeedDataType.YcbcrSep;
        if (!forPose && !forHands && !twoPlanes)
        {
            return;
        }

        byte[] rgb;
        int width;
        int height;
        if (twoPlanes)
        {
            // NOTE (mristin):
            // A two-plane feed has no RGB texture, so we convert it ourselves, on
            // every frame, as the preview needs it, too.
            Image? luma = CameraTexture.GetImage();
            Image? chroma = _cbcrTexture?.GetImage();
            if (luma == null || luma.IsEmpty() || chroma == null || chroma.IsEmpty())
            {
                return;
            }

            (rgb, width, height) = YcbcrToRgb(luma, chroma, _maxYcbcrWidth);
            var preview = Image.CreateFromData(width, height, false, Image.Format.Rgb8, rgb);
            if (_ycbcrPreview == null || _ycbcrPreview.GetSize() != preview.GetSize())
            {
                _ycbcrPreview = ImageTexture.CreateFromImage(preview);
            }
            else
            {
                _ycbcrPreview.Update(preview);
            }

            if (!forPose && !forHands)
            {
                return;
            }
        }
        else
        {
            Image? image = CameraTexture.GetImage();
            if (image == null || image.IsEmpty())
            {
                return;
            }

            if (image.GetFormat() != Image.Format.Rgb8)
            {
                image.Convert(Image.Format.Rgb8);
            }

            rgb = image.GetData();
            width = image.GetWidth();
            height = image.GetHeight();
        }

        // NOTE (mristin):
        // We copy the raw bytes on the main thread so that the pose thread
        // never touches any engine objects.
        var frame = new Frame(rgb, width, height, Now);
        if (forPose)
        {
            _poseSlot.Put(frame);
        }

        if (forHands)
        {
            _handSlot.Put(frame);
        }
    }

    /// <summary>Convert a Y plane and a CbCr plane of the camera to RGB8.</summary>
    private static (byte[] Rgb, int Width, int Height) YcbcrToRgb(Image luma, Image chroma, int maxWidth)
    {
        if (luma.GetFormat() != Image.Format.R8)
        {
            luma.Convert(Image.Format.R8);
        }

        if (chroma.GetFormat() != Image.Format.Rg8)
        {
            chroma.Convert(Image.Format.Rg8);
        }

        return YcbcrConverter.ToRgb(
            luma.GetData(), luma.GetWidth(), luma.GetHeight(),
            chroma.GetData(), chroma.GetWidth(), chroma.GetHeight(),
            maxWidth);
    }

    /// <summary>
    /// Activate the feed again if it did not start, which happens on macOS on the
    /// first start: the feed asks for the permission and stays off even when the
    /// player grants it.
    /// </summary>
    private void RetryActivation(double now)
    {
        if (_feed == null || _feed.FeedIsActive || double.IsNaN(_nextActivationAttempt)
            || now < _nextActivationAttempt)
        {
            return;
        }

        _nextActivationAttempt = now + _activationRetryPeriod;
        GD.Print("The camera did not start; trying again (maybe the camera permission was just granted).");
        _feed.FeedIsActive = true;
        if (CameraTexture != null)
        {
            CameraTexture.CameraIsActive = true;
        }

        if (_cbcrTexture != null)
        {
            _cbcrTexture.CameraIsActive = true;
        }
    }

    /// <summary>Ask for the next camera frame and wait for it; null on a timeout or the exit.</summary>
    private Frame? NextFrame(FrameSlot slot)
    {
        slot.Requested = true;
        if (!slot.Ready.WaitOne(500) || !_running)
        {
            return null;
        }

        return slot.Take();
    }

    private void HandLoop(byte[] model)
    {
        YoloxHeadDetector? detector = null;
        try
        {
            detector = new YoloxHeadDetector(model);
            var heads = new List<Detection>();
            while (_running)
            {
                if (!_handTracking)
                {
                    Thread.Sleep(50);
                    continue;
                }

                var frame = NextFrame(_handSlot);
                if (frame == null)
                {
                    continue;
                }

                detector.Detect(frame, heads);
                var hands = new List<BoundingBox>();
                foreach (var hand in detector.Hands)
                {
                    hands.Add(hand.Box);
                }

                Volatile.Write(ref _latestHands, new HandSnapshot
                {
                    Timestamp = frame.Timestamp,
                    Width = frame.Width,
                    Height = frame.Height,
                    Hands = hands,
                });
            }
        }
        catch (Exception exception)
        {
            // NOTE (mristin):
            // Without the hands, the screens still work with the mouse.
            GD.PushWarning($"The hand detector stopped: {exception}");
        }
        finally
        {
            detector?.Dispose();
        }
    }

    private void PoseLoop(byte[] rtmo, byte[] rtmPose, int threads)
    {
        PoseFollower? follower = null;
        try
        {
            follower = new PoseFollower(rtmo, rtmPose, threads);
            Callable.From(() => SetStatus(ServiceStatus.Running, "")).CallDeferred();

            while (_running)
            {
                var frame = NextFrame(_poseSlot);
                if (frame != null)
                {
                    Volatile.Write(ref _latest, follower.Process(frame, 1));
                }
            }
        }
        catch (Exception exception)
        {
            GD.PushError($"The vision failed: {exception}");
            string message = $"The vision failed: {exception.Message}";
            Callable.From(() => SetStatus(ServiceStatus.Failed, message)).CallDeferred();
        }
        finally
        {
            follower?.Dispose();
        }
    }

    private void SetStatus(ServiceStatus status, string message)
    {
        Status = status;
        StatusMessage = message;
        GD.Print($"Vision: {status}: {message}");
    }

    public override void _Notification(int what)
    {
        if (what == NotificationWMCloseRequest)
        {
            Shutdown();
        }
    }

    public override void _ExitTree() => Shutdown();

    /// <summary>
    /// Stop the camera and the pose thread; call it before quitting, so that no
    /// camera frame arrives while the engine shuts down. Calling it again does
    /// nothing.
    /// </summary>
    public void Shutdown()
    {
        if (_shutDown)
        {
            return;
        }

        _shutDown = true;
        _running = false;
        _poseSlot.Ready.Set();
        _handSlot.Ready.Set();
        _poseThread?.Join(2000);
        _poseThread = null;
        _handThread?.Join(2000);
        _handThread = null;

        if (_feed != null)
        {
            _feed.FrameChanged -= OnFrameChanged;
            _feed.FeedIsActive = false;
            _feed = null;
        }

        if (CameraTexture != null)
        {
            CameraTexture.CameraIsActive = false;
            CameraTexture = null;
        }

        if (_cbcrTexture != null)
        {
            _cbcrTexture.CameraIsActive = false;
            _cbcrTexture = null;
        }

        _ycbcrPreview = null;

        // NOTE (mristin):
        // The extension removes its feeds when it is freed, so it goes last.
        _cameraExtension = null;
    }
}
