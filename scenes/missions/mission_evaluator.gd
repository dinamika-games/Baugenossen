class_name MissionEvaluator
extends RefCounted
## Evaluate a mission on its site (DESIGN.md, 5): every mandatory objective must
## pass to submit, the optional ones never block. Run it after each edit, not on
## every frame.


class Report:
    extends RefCounted
    var mandatory: Array[Dictionary] = []
    var optional: Array[Dictionary] = []
    var analysis: SiteAnalysis

    func can_submit() -> bool:
        for result in mandatory:
            if not result["satisfied"]:
                return false
        return true

    func satisfied_optional_ids() -> Array[String]:
        var ids: Array[String] = []
        for result in optional:
            if result["satisfied"]:
                ids.append(str(result["id"]))
        return ids


static func evaluate(mission: Dictionary, grid: WorldGrid) -> Report:
    var report := Report.new()
    report.analysis = SiteAnalysis.analyse(grid)
    for objective in mission["mandatory_objectives"]:
        report.mandatory.append(Objectives.evaluate(objective, report.analysis, mission))
    for objective in mission["optional_objectives"]:
        report.optional.append(Objectives.evaluate(objective, report.analysis, mission))
    return report
