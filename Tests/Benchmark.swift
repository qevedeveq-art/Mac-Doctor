import Foundation
import AppKit
import Darwin

func seconds(_ r:rusage)->Double { Double(r.ru_utime.tv_sec)+Double(r.ru_utime.tv_usec)/1_000_000 + Double(r.ru_stime.tv_sec)+Double(r.ru_stime.tv_usec)/1_000_000 }
@main struct Benchmark {
 static func main() throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("macpilot-benchmark-\(UUID().uuidString)");try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let model=Monitor(storageDirectory:root,automatic:false); model.macmonEnabled=false;model.alertsEnabled=false
  var before=rusage(),beforeChildren=rusage();getrusage(RUSAGE_SELF,&before);getrusage(RUSAGE_CHILDREN,&beforeChildren);let started=Date()
  for _ in 0..<4 { model.refresh();let until=Date().addingTimeInterval(45);while model.busy && Date()<until {RunLoop.current.run(until:Date().addingTimeInterval(0.05))}; if model.busy {fputs("collecte expirée\n",stderr);exit(1)} }
  var after=rusage(),afterChildren=rusage();getrusage(RUSAGE_SELF,&after);getrusage(RUSAGE_CHILDREN,&afterChildren)
  print(String(format:"4 relevés, temps écoulé %.2f s, CPU parent %.3f s, CPU enfants %.3f s, RSS max %.1f Mo",Date().timeIntervalSince(started),seconds(after)-seconds(before),seconds(afterChildren)-seconds(beforeChildren),Double(after.ru_maxrss)/1_000_000))
 }
}
