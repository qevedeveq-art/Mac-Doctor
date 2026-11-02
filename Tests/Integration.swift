import Foundation
import AppKit

@main struct Integration {
 static func main() throws {
  func check(_ b:@autoclosure()->Bool,_ text:String) { guard b() else { fputs("FAIL: \(text)\n",stderr); exit(1) }; print("OK: \(text)") }
  func wait(_ max:TimeInterval,_ predicate:()->Bool)->Bool { let end=Date().addingTimeInterval(max); while Date()<end { if predicate(){return true}; RunLoop.current.run(until:Date().addingTimeInterval(0.05)) };return predicate() }
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("macpilot-integration-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:root) }
  let path=CommandLine.arguments[1]
  let fixture=root.appendingPathComponent("fixture"); try FileManager.default.createDirectory(at:fixture,withIntermediateDirectories:true)
  let fake=URL(fileURLWithPath:CommandLine.arguments[2])
  try Data(repeating:0,count:1024).write(to:fixture.appendingPathComponent("sample.dat"))
  let child=Process(); child.executableURL=fake; child.arguments=[]; try child.run(); defer {if child.isRunning {child.terminate();child.waitUntilExit()}}
  var model:Monitor?=Monitor(storageDirectory:root,macmonPath:path,automatic:false); model!.alertsEnabled=false; model!.macmonEnabled=true
  check(model!.canPersist,"verrou acquis sur historique isolé")
  var duplicate:Monitor?=Monitor(storageDirectory:root,macmonPath:path,automatic:false); check(duplicate!.paused && !duplicate!.canPersist,"seconde instance en pause"); duplicate=nil
  model!.refresh(); check(wait(45){!model!.busy && !model!.samples.isEmpty},"collecte réelle terminée")
  check(!model!.processes.isEmpty,"processus disponibles")
  check(model!.samples.last?.cpu != nil,"CPU macOS lu")
  check(model!.samples.last?.memoryFree != nil,"marge mémoire lue")
  if let battery=readBattery(), let sampled=model!.samples.last?.battery { check(abs(battery.percent-sampled)<=1,"batterie native cohérente avec le relevé") }
  model!.refresh(); check(wait(45){!model!.busy && model!.samples.count >= 2},"second relevé terminé"); check(model!.samples.last?.cpu != nil && model!.cpu.contains("mesure macOS"),"delta CPU natif utilisable")
  check(model!.latestMacMetrics != nil,"macmon intégré relevé réel")
  check(FileManager.default.fileExists(atPath:root.appendingPathComponent("history.sqlite").path),"historique temporaire écrit")
  guard let p=model!.processes.first(where:{$0.id==child.processIdentifier}) else {fputs("FAIL: processus de test introuvable\n",stderr);exit(1)}
  check(model!.isSame(p),"identité du processus de test vérifiée")
  let result=model!.terminate(p); check(result.hasPrefix("Demande"),"demande d’arrêt du processus de test")
  check(wait(5){!child.isRunning},"processus de test arrêté")
  check(FileManager.default.fileExists(atPath:root.appendingPathComponent("actions.json").path),"journal temporaire écrit")
  model!.analyzeFolder(fixture); check(wait(30){!model!.storageBusy},"analyse Mole terminée")
  check(model!.storageRows.contains(where:{$0.url.lastPathComponent == "sample.dat"}),"élément du dossier de test présent")
  model!.readMoleStatus(); check(wait(30){!model!.moleStatusBusy},"état Mole terminé")
  check(model!.moleStatus.contains("CPU :"),"état Mole lisible")
  let count=model!.samples.count; model!.togglePause(); model!.refresh(); RunLoop.current.run(until:Date().addingTimeInterval(0.2)); check(model!.samples.count==count,"collecte suspendue"); model!.togglePause(); model!.togglePause(); check(wait(45){!model!.busy},"collecte interrompue terminée"); check(model!.samples.count==count,"résultat périmé après pause ignoré")
  model=nil; let again=Monitor(storageDirectory:root,macmonPath:path,automatic:false); check(again.canPersist,"verrou libéré après fermeture"); check(!again.samples.isEmpty,"historique relu après redémarrage"); again.clearData(); check(again.samples.isEmpty && again.actionRecords.isEmpty,"effacement isolé des données"); let store=try HistoryStore(url:root.appendingPathComponent("history.sqlite")); let decoded=try store.load(since:Date.distantPast); check(decoded.isEmpty,"effacement persistant vérifié"); let migration=root.appendingPathComponent("migration"); try FileManager.default.createDirectory(at:migration,withIntermediateDirectories:true); let legacy=Sample(time:Date(),cpu:12,gpu:nil,battery:80,onBattery:true); try JSONEncoder().encode([legacy]).write(to:migration.appendingPathComponent("history.json")); let migrated=Monitor(storageDirectory:migration,automatic:false); check(migrated.samples.count==1 && migrated.samples.first?.id==legacy.id,"migration de l’historique JSON"); let backup=try JSONDecoder().decode([Sample].self,from:Data(contentsOf:migration.appendingPathComponent("history.json"))); check(backup.isEmpty,"ancien historique effacé après migration réussie"); let badDir=root.appendingPathComponent("bad");try FileManager.default.createDirectory(at:badDir,withIntermediateDirectories:true);let bad=badDir.appendingPathComponent("history.json");try Data("not json".utf8).write(to:bad);let damaged=Monitor(storageDirectory:badDir,automatic:false);check(damaged.paused && !damaged.canPersist && !damaged.persistenceWarning.isEmpty,"migration corrompue mise en pause");let preserved=try Data(contentsOf:bad);check(preserved==Data("not json".utf8),"ancien fichier corrompu conservé");let expiry=root.appendingPathComponent("expiry");try FileManager.default.createDirectory(at:expiry,withIntermediateDirectories:true);let e=try HistoryStore(url:expiry.appendingPathComponent("history.sqlite"));let old=Sample(time:Date().addingTimeInterval(-172800),cpu:1,gpu:nil,battery:nil,onBattery:false);let recent=Sample(time:Date(),cpu:2,gpu:nil,battery:nil,onBattery:false);try e.append([old,recent]);try e.prune(before:Date().addingTimeInterval(-86400));let kept=try e.load(since:Date.distantPast);check(kept.count==1 && kept[0].id==recent.id,"expiration des anciens relevés")
 }
}
