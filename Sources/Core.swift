import Foundation
import Darwin
import IOKit.ps

struct CommandResult {
 let output:String
 let exitCode:Int32?
 let timedOut:Bool
 var succeeded:Bool { exitCode == 0 && !timedOut }
}
func boundedCommand(_ path:String,_ args:[String]=[], timeout:TimeInterval=8, maximumBytes:Int=1_000_000)->CommandResult {
 let task=Process(); task.executableURL=URL(fileURLWithPath:path); task.arguments=args; task.standardInput=FileHandle.nullDevice; var env=ProcessInfo.processInfo.environment; env["LC_ALL"]="C"; task.environment=env
 let url=FileManager.default.temporaryDirectory.appendingPathComponent("macpilot-\(UUID().uuidString)")
 guard FileManager.default.createFile(atPath:url.path,contents:nil,attributes:[.posixPermissions:0o600]), let file=try? FileHandle(forWritingTo:url) else { return CommandResult(output:"Impossible de créer le fichier temporaire.",exitCode:nil,timedOut:false) }
 defer { try? file.close(); try? FileManager.default.removeItem(at:url) }
 task.standardOutput=file; task.standardError=file
 let finished=DispatchSemaphore(value:0); task.terminationHandler={_ in finished.signal()}
 do { try task.run() } catch { return CommandResult(output:error.localizedDescription,exitCode:nil,timedOut:false) }
 let timedOut=finished.wait(timeout:.now()+timeout) == .timedOut
 if timedOut && task.isRunning { task.terminate(); if finished.wait(timeout:.now()+0.5) == .timedOut && task.isRunning { _=Darwin.kill(task.processIdentifier,SIGKILL) } }
 task.waitUntilExit(); try? file.synchronize()
 let read=try? FileHandle(forReadingFrom:url); let data=(try? read?.read(upToCount:maximumBytes)) ?? nil; try? read?.close()
 return CommandResult(output:String(decoding:data ?? Data(),as:UTF8.self),exitCode:task.terminationStatus,timedOut:timedOut)
}
func processIdentityMatches(_ line:String,user:String,start:String,command:String)->Bool {
 let fields=line.trimmingCharacters(in:.whitespacesAndNewlines).split(maxSplits:6,whereSeparator:{$0 == " " || $0 == "\t"})
 return fields.count == 7 && String(fields[0]) == user && fields[1...5].joined(separator:" ") == start && String(fields[6]).trimmingCharacters(in:.whitespaces) == command
}
func dischargeRate(first:Double,last:Double,seconds:TimeInterval)->Double? {
 guard seconds >= 600, first >= last, (0...100).contains(first), (0...100).contains(last) else{return nil}
 return (first-last)/(seconds/3600)
}

func continuousBatterySamples(_ observations:[(Date,Bool)], maxGap:TimeInterval=45)->Bool {
 guard observations.count >= 2, observations.allSatisfy({$0.1}) else{return false}
 return zip(observations,observations.dropFirst()).allSatisfy { a,b in let gap=b.0.timeIntervalSince(a.0); return gap>0 && gap<=maxGap }
}

func volumeCommand(_ value:Int)->String? { guard (0...100).contains(value) else {return nil}; return "set volume output volume \(value)" }

struct MacMetrics { let cpuW:Double?; let gpuW:Double?; let systemW:Double?; let cpuTemp:Double? }
func parseMacmon(_ text:String)->MacMetrics? {
 guard let line=text.split(separator:"\n").last, let data=String(line).data(using:.utf8), let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else{return nil}
 func positive(_ value:Any?, max:Double)->Double? { guard let x=value as? Double, x.isFinite, x>0, x<=max else{return nil};return x }
 let temp=object["temp"] as? [String:Any] ?? [:]
 return MacMetrics(cpuW:positive(object["cpu_power"],max:500),gpuW:positive(object["gpu_power"],max:500),systemW:positive(object["sys_power"],max:500),cpuTemp:positive(temp["cpu_temp_avg"],max:150))
}
struct MoleItem { let name:String; let path:String; let bytes:Int64; let status:String? }
func parseMoleAnalysis(_ data:Data)->(items:[MoleItem],status:String?)? {
 guard let obj=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any], let entries=obj["entries"] as? [[String:Any]] else{return nil}
 let items=entries.compactMap{ e -> MoleItem? in guard let name=e["name"] as? String, let path=e["path"] as? String, let value=e["size"] as? NSNumber, value.int64Value >= 0 else{return nil};return MoleItem(name:name,path:path,bytes:value.int64Value,status:e["scan_status"] as? String) }
 return (items,obj["scan_status"] as? String)
}

enum CollectionProfile:String,CaseIterable { case precise="Précis", balanced="Équilibré", economy="Économie" }
func collectionInterval(profile:CollectionProfile, foreground:Bool, onBattery:Bool, lowPower:Bool)->TimeInterval {
 if lowPower || profile == .economy { return 60 }
 if onBattery { return foreground ? 30 : 60 }
 if foreground { return profile == .precise ? 5 : 8 }
 return 30
}

struct CPUTicks { let user:UInt32; let system:UInt32; let idle:UInt32; let nice:UInt32 }
func cpuUsage(previous:CPUTicks,current:CPUTicks)->Double? {
 let u=UInt64(current.user &- previous.user), s=UInt64(current.system &- previous.system), i=UInt64(current.idle &- previous.idle), n=UInt64(current.nice &- previous.nice)
 let total=u+s+i+n; guard total > 0 else{return nil};return Double(u+s+n)*100.0/Double(total)
}
func readCPUTicks()->CPUTicks? {
 var info=host_cpu_load_info(); var count=mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
 let status=withUnsafeMutablePointer(to:&info){p in p.withMemoryRebound(to:integer_t.self,capacity:Int(count)){host_statistics(mach_host_self(),HOST_CPU_LOAD_INFO,$0,&count)} }
 guard status == KERN_SUCCESS else{return nil};return CPUTicks(user:info.cpu_ticks.0,system:info.cpu_ticks.1,idle:info.cpu_ticks.2,nice:info.cpu_ticks.3)
}
final class CPUTracker {
 private var last:CPUTicks?; private var generation:Int = -1
 func sample(generation:Int)->Double? { if self.generation != generation { last=nil;self.generation=generation };guard let now=readCPUTicks() else {last=nil;return nil};defer{last=now};guard let previous=last else{return nil};return cpuUsage(previous:previous,current:now) }
}

struct BatteryReading { let percent:Double; let onBattery:Bool; let charging:Bool }
func parseBattery(_ values:[String:Any])->BatteryReading? {
 guard let current=values["Current Capacity"] as? NSNumber, let maximum=values["Max Capacity"] as? NSNumber, maximum.doubleValue > 0, let state=values["Power Source State"] as? String, state == "Battery Power" || state == "AC Power" else{return nil}
 let value=current.doubleValue / maximum.doubleValue * 100; guard value.isFinite, (0...100).contains(value) else{return nil}
 return BatteryReading(percent:value,onBattery:state == "Battery Power",charging:(values["Is Charging"] as? NSNumber)?.boolValue ?? false)
}

func readBattery()->BatteryReading? {
 guard let info=IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list=IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else{return nil}
 for source in list { guard let values=IOPSGetPowerSourceDescription(info,source)?.takeUnretainedValue() as? [String:Any], (values["Type"] as? String) == "InternalBattery" else{continue}; if let battery=parseBattery(values){return battery} };return nil
}

func shouldConserve(profile:CollectionProfile,lowPower:Bool,onBattery:Bool?)->Bool {
 return profile == .economy || lowPower || (onBattery != false)
}

func batteryMaximumGap(interval:TimeInterval)->TimeInterval { max(45, min(180, interval * 1.8)) }

enum ReadingFreshness:Equatable { case unavailable, paused, current, stale }
func readingFreshness(last:Date?, now:Date, interval:TimeInterval, paused:Bool)->ReadingFreshness {
 guard let last=last else{return .unavailable}
 if paused{return .paused}
 let age=now.timeIntervalSince(last)
 guard age >= 0, interval.isFinite, interval > 0 else{return .stale}
 return age <= max(30,interval*2.5) ? .current : .stale
}

struct InterfaceCounters { let received:UInt64; let sent:UInt64 }
struct NetworkCounters { let interfaces:[String:InterfaceCounters] }
struct InterfaceRate:Identifiable { let id:String; let received:Double; let sent:Double }
struct NetworkRate { let received:Double; let sent:Double; let interfaces:[InterfaceRate] }
func networkRate(previous:NetworkCounters,current:NetworkCounters,seconds:TimeInterval)->NetworkRate? {
 guard seconds > 0, seconds.isFinite, !current.interfaces.isEmpty, Set(previous.interfaces.keys) == Set(current.interfaces.keys) else {return nil}
 var rates:[InterfaceRate]=[]
 for name in current.interfaces.keys.sorted() { guard let old=previous.interfaces[name], let new=current.interfaces[name], new.received >= old.received, new.sent >= old.sent else{return nil}; rates.append(InterfaceRate(id:name,received:Double(new.received-old.received)/seconds,sent:Double(new.sent-old.sent)/seconds)) }
 return NetworkRate(received:rates.reduce(0){$0+$1.received},sent:rates.reduce(0){$0+$1.sent},interfaces:rates)
}
func readNetworkCounters()->NetworkCounters? {
 var list:UnsafeMutablePointer<ifaddrs>?; guard getifaddrs(&list) == 0, let first=list else{return nil}; defer{freeifaddrs(list)}
 var entries:[String:InterfaceCounters]=[:]; var cursor:UnsafeMutablePointer<ifaddrs>?=first
 while let item=cursor { let entry=item.pointee; defer{cursor=entry.ifa_next}; guard let address=entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK), entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0, let data=entry.ifa_data, let name=entry.ifa_name else{continue}; let key=String(cString:name); guard entries[key] == nil else{continue}; let stats=data.assumingMemoryBound(to:if_data.self).pointee; entries[key]=InterfaceCounters(received:UInt64(stats.ifi_ibytes),sent:UInt64(stats.ifi_obytes)) }
 return entries.isEmpty ? nil : NetworkCounters(interfaces:entries)
}
final class NetworkTracker {
 private var previous:(NetworkCounters,Date)?; private var generation:Int = -1
 func sample(generation:Int)->NetworkRate? { if self.generation != generation {previous=nil;self.generation=generation}; guard let counters=readNetworkCounters() else{previous=nil;return nil};let now=Date(); defer{previous=(counters,now)};guard let old=previous else{return nil};return networkRate(previous:old.0,current:counters,seconds:now.timeIntervalSince(old.1)) }
}

// The registry identifier keeps counters distinct when devices appear or disappear.
func parseDiskCounters(_ text:String)->NetworkCounters? {
 guard let data=text.data(using:.utf8), let entries=(try? PropertyListSerialization.propertyList(from:data,options:[],format:nil)) as? [[String:Any]] else{return nil}
 var counters:[String:InterfaceCounters]=[:]
 for entry in entries {
  guard let id=entry["IORegistryEntryID"] as? NSNumber, let stats=entry["Statistics"] as? [String:Any], let read=stats["Bytes (Read)"] as? NSNumber, let write=stats["Bytes (Write)"] as? NSNumber, read.int64Value >= 0, write.int64Value >= 0 else{continue}
  let key=id.stringValue; guard counters[key] == nil else{return nil}
  counters[key]=InterfaceCounters(received:read.uint64Value,sent:write.uint64Value)
 }
 return counters.isEmpty ? nil : NetworkCounters(interfaces:counters)
}
final class DiskTracker {
 private var previous:(NetworkCounters,Date)?; private var generation:Int = -1
 func sample(_ counters:NetworkCounters?,now:Date,generation:Int)->NetworkRate? {
  if self.generation != generation {previous=nil;self.generation=generation}
  guard let counters=counters else{previous=nil;return nil}; defer{previous=(counters,now)}
  guard let old=previous else{return nil}
  return networkRate(previous:old.0,current:counters,seconds:now.timeIntervalSince(old.1))
 }
}
