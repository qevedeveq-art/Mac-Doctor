import Foundation

@main struct Tests {
 static func main() {
  func check(_ ok:@autoclosure ()->Bool,_ name:String) { if !ok() { fputs("FAIL: \(name)\n",stderr); exit(1) }; print("OK: \(name)") }
  let line="alice   Sun Nov  1 14:35:13 2026    /Applications/My App.app/Contents/MacOS/app --flag a"
  check(processIdentityMatches(line,user:"alice",start:"Sun Nov 1 14:35:13 2026",command:"/Applications/My App.app/Contents/MacOS/app --flag a"),"processus avec espaces")
  check(!processIdentityMatches(line,user:"alice",start:"Sun Nov 1 14:35:14 2026",command:"/Applications/My App.app/Contents/MacOS/app --flag a"),"PID réutilisé")
  check(!processIdentityMatches(line,user:"alice",start:"Sun Nov 1 14:35:13 2026",command:"/Applications/My App.app/Contents/MacOS/app"),"commande partielle")
  check(dischargeRate(first:80,last:70,seconds:3600)==10,"décharge")
  check(dischargeRate(first:70,last:80,seconds:3600)==nil,"charge non interprétée comme décharge")
  check(dischargeRate(first:80,last:70,seconds:599)==nil,"mesure trop courte")
  let now=Date(); let a=[(now,true),(now.addingTimeInterval(8),true),(now.addingTimeInterval(16),true)]; check(continuousBatterySamples(a),"échantillons continus sur batterie"); check(!continuousBatterySamples([(now,true),(now.addingTimeInterval(90),true)]),"trou de mesure"); check(!continuousBatterySamples([(now,true),(now.addingTimeInterval(8),false)]),"passage sur secteur")
  check(volumeCommand(0)=="set volume output volume 0", "volume minimum"); check(volumeCommand(100)=="set volume output volume 100", "volume maximum"); check(volumeCommand(-1)==nil && volumeCommand(101)==nil,"rejet du volume invalide")
  let parsed=parseMacmon("{\"cpu_power\":2.5,\"gpu_power\":0,\"sys_power\":8,\"temp\":{\"cpu_temp_avg\":45}}")
  check(parsed?.cpuW==2.5 && parsed?.gpuW==nil && parsed?.systemW==8 && parsed?.cpuTemp==45,"macmon valeurs et indisponibilité")
  check(parseMacmon("non-json")==nil,"macmon JSON invalide")
  let moleData="{\"entries\":[{\"name\":\"A\",\"path\":\"/tmp/A\",\"size\":1024}]}".data(using:.utf8)!
  let scan=parseMoleAnalysis(moleData); check(scan?.items.count==1 && scan?.items.first?.bytes==1024 && scan?.status==nil,"Mole sans indication de complétude")
  check(parseMoleAnalysis(Data("{}".utf8))==nil,"Mole sans liste")
  let fixture=FileManager.default.temporaryDirectory.appendingPathComponent("macpilot-test-\(UUID().uuidString)"); try! FileManager.default.createDirectory(at:fixture,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:fixture) }; try! Data(repeating:7,count:2048).write(to:fixture.appendingPathComponent("sample.dat"))
  if FileManager.default.isExecutableFile(atPath:"/opt/homebrew/bin/mo") { let analysis=boundedCommand("/opt/homebrew/bin/mo",["analyze","--json",fixture.path],timeout:15); let realScan=parseMoleAnalysis(Data(analysis.output.utf8)); check(analysis.succeeded && realScan?.items.contains(where:{$0.name=="sample.dat"}) == true,"analyse Mole réelle sur un dossier de test") } else { print("SKIP: Mole absent") }
  if CommandLine.arguments.count > 1 { let sample=boundedCommand(CommandLine.arguments[1],["pipe","-s","2","-i","1000"],timeout:12); let values=parseMacmon(sample.output); check(sample.succeeded && values != nil,"macmon réel : relevé JSON") }
  check(collectionInterval(profile:.balanced,foreground:true,onBattery:false,lowPower:false)==8,"profil actif")
  check(collectionInterval(profile:.balanced,foreground:false,onBattery:true,lowPower:false)==60,"profil batterie arrière-plan")
  check(collectionInterval(profile:.precise,foreground:true,onBattery:false,lowPower:true)==60,"mode économie système")
  let prev=CPUTicks(user:100,system:100,idle:100,nice:100), curr=CPUTicks(user:110,system:105,idle:125,nice:100)
  check(cpuUsage(previous:prev,current:curr)==37.5,"calcul CPU natif")
  check(cpuUsage(previous:prev,current:prev)==nil,"CPU sans intervalle")
  check(readCPUTicks() != nil,"compteurs CPU natifs disponibles")
  let netA=NetworkCounters(received:100,sent:200,interfaces:["en0"]), netB=NetworkCounters(received:500,sent:400,interfaces:["en0"])
  let rate=networkRate(previous:netA,current:netB,seconds:2); check(rate?.received==200 && rate?.sent==100,"débit réseau moyen")
  check(networkRate(previous:netB,current:netA,seconds:2)==nil,"compteurs réseau réinitialisés")
  check(networkRate(previous:netA,current:NetworkCounters(received:500,sent:400,interfaces:["en1"]),seconds:2)==nil,"changement d’interface réseau")
  check(networkRate(previous:netA,current:netB,seconds:0)==nil,"intervalle réseau nul")
  check(readNetworkCounters() != nil,"compteurs réseau natifs disponibles")
  let nativeBattery=parseBattery(["Current Capacity":86,"Max Capacity":100,"Power Source State":"Battery Power","Is Charging":false]); check(nativeBattery?.percent==86 && nativeBattery?.onBattery==true,"batterie native sur batterie")
  check(parseBattery(["Current Capacity":86,"Max Capacity":0,"Power Source State":"Battery Power"])==nil,"capacité batterie invalide")
  check(parseBattery(["Current Capacity":86,"Max Capacity":100,"Power Source State":"unknown"])==nil,"alimentation inconnue")
  check(shouldConserve(profile:.balanced,lowPower:false,onBattery:nil),"source inconnue : mode prudent")
  check(!shouldConserve(profile:.balanced,lowPower:false,onBattery:false),"secteur connu : collecteur possible")
  check(shouldConserve(profile:.balanced,lowPower:false,onBattery:true),"sur batterie : mode prudent")
  check(batteryMaximumGap(interval:8)==45,"tolérance des relevés rapides"); check(batteryMaximumGap(interval:60)==108,"tolérance du profil économie"); check(batteryMaximumGap(interval:1000)==180,"plafond du trou de mesure")
  check(readingFreshness(last:nil,now:now,interval:8,paused:false) == .unavailable,"mesure absente")
  check(readingFreshness(last:now,now:now,interval:8,paused:true) == .paused,"mesure en pause")
  check(readingFreshness(last:now.addingTimeInterval(-50),now:now,interval:60,paused:false) == .current,"mesure récente en mode économie")
  check(readingFreshness(last:now.addingTimeInterval(-151),now:now,interval:60,paused:false) == .stale,"mesure ancienne")
  check(readingFreshness(last:now.addingTimeInterval(5),now:now,interval:8,paused:false) == .stale,"horodatage futur")
  let ok=boundedCommand("/bin/echo",["bonjour"],timeout:2); check(ok.succeeded && ok.output.contains("bonjour"),"commande normale")
  let fail=boundedCommand("/usr/bin/false",[],timeout:2); check(!fail.succeeded && !fail.timedOut,"code d’échec")
  let child=Process(); child.executableURL=URL(fileURLWithPath:"/bin/sleep"); child.arguments=["30"]; try! child.run(); let id=child.processIdentifier
  let details=boundedCommand("/bin/ps",["-p",String(id),"-o","user=,lstart=,command="],timeout:3)
  let fields=details.output.trimmingCharacters(in:.whitespacesAndNewlines).split(maxSplits:6,whereSeparator:{$0 == " " || $0 == "\t"})
  check(details.succeeded && fields.count == 7,"lecture d’un processus de test réel")
  let start=fields[1...5].joined(separator:" "); let command=String(fields[6]).trimmingCharacters(in:.whitespaces)
  check(processIdentityMatches(details.output,user:NSUserName(),start:start,command:command),"identité du processus de test réel")
  child.terminate(); child.waitUntilExit(); check(!child.isRunning,"fermeture du seul processus de test")
  let slow=boundedCommand("/bin/sleep",["2"],timeout:0.2); check(slow.timedOut && !slow.succeeded,"limite de durée")
 }
}
