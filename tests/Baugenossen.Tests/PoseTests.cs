using Baugenossen.Vision;
using Xunit;

namespace Baugenossen.Tests
{
    public class PoseTests
    {
        private static Pose MakePose(float shoulderLeftX, float shoulderRightX, float y, float score)
        {
            var keypoints = new Keypoint[Pose.KeypointCount];
            for (int i = 0; i < keypoints.Length; i++)
            {
                keypoints[i] = new Keypoint(0f, 0f, 0f);
            }

            keypoints[(int)BodyPart.Nose] = new Keypoint((shoulderLeftX + shoulderRightX) / 2f, y - 50f, score);
            keypoints[(int)BodyPart.LeftShoulder] = new Keypoint(shoulderLeftX, y, score);
            keypoints[(int)BodyPart.RightShoulder] = new Keypoint(shoulderRightX, y, score);
            return new Pose(keypoints, new BoundingBox(0f, 0f, 10f, 10f), score);
        }

        [Fact]
        public void Unit_is_the_width_of_the_shoulders()
        {
            var pose = MakePose(400f, 300f, 200f, 0.9f);
            Assert.Equal(100f, pose.Unit(0.3f)!.Value, 3);
        }

        [Fact]
        public void Unit_is_null_without_confident_key_points()
        {
            var pose = MakePose(400f, 300f, 200f, 0.1f);
            Assert.Null(pose.Unit(0.3f));
        }

        [Fact]
        public void Selection_prefers_the_closest_person()
        {
            var far = MakePose(330f, 310f, 200f, 0.9f);
            var near = MakePose(400f, 250f, 200f, 0.9f);
            var picked = PlayerSelection.Pick(new[] { far, near }, 0.3f, 640);
            Assert.Same(near, picked);
        }
    }
}
