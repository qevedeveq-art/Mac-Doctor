import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
final class HistoryStore {
 private var db:OpaquePointer?
 init(url:URL) throws {
  let status=sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_FULLMUTEX,nil)
  guard status == SQLITE_OK else { let message=db.map{String(cString:sqlite3_errmsg($0))} ?? "ouverture impossible"; if let db=db {sqlite3_close(db)}; self.db=nil; throw NSError(domain:"MacPilotHistory",code:Int(status),userInfo:[NSLocalizedDescriptionKey:message]) }
  do { try execute("CREATE TABLE IF NOT EXISTS samples (id TEXT PRIMARY KEY, t REAL NOT NULL, data BLOB NOT NULL)"); try execute("CREATE INDEX IF NOT EXISTS sample_time ON samples(t)") } catch { if let db=db {sqlite3_close(db)}; self.db=nil; throw error }
 }
 deinit { if let db=db {sqlite3_close(db)} }
 private func fail(_ code:Int32)->NSError { NSError(domain:"MacPilotHistory",code:Int(code),userInfo:[NSLocalizedDescriptionKey:db.map{String(cString:sqlite3_errmsg($0))} ?? "Base inaccessible"]) }
 private func execute(_ sql:String)throws { let rc=sqlite3_exec(db,sql,nil,nil,nil); guard rc == SQLITE_OK else {throw fail(rc)} }
 func append(_ samples:[Sample])throws {
  guard !samples.isEmpty else{return}; try execute("BEGIN IMMEDIATE")
  do {
   var stmt:OpaquePointer?; let rc=sqlite3_prepare_v2(db,"INSERT OR IGNORE INTO samples(id,t,data) VALUES(?,?,?)",-1,&stmt,nil); guard rc == SQLITE_OK, let q=stmt else {throw fail(rc)}; defer {sqlite3_finalize(q)}
   for sample in samples { let data=try JSONEncoder().encode(sample); sqlite3_reset(q);sqlite3_clear_bindings(q); sqlite3_bind_text(q,1,sample.id.uuidString,-1,sqliteTransient);sqlite3_bind_double(q,2,sample.time.timeIntervalSince1970); data.withUnsafeBytes{_ = sqlite3_bind_blob(q,3,$0.baseAddress,Int32(data.count),sqliteTransient)}; let r=sqlite3_step(q);guard r == SQLITE_DONE else {throw fail(r)} }
   try execute("COMMIT")
  } catch {try? execute("ROLLBACK");throw error}
 }
 func load(since:Date)throws->[Sample] {
  var stmt:OpaquePointer?; let rc=sqlite3_prepare_v2(db,"SELECT data FROM samples WHERE t >= ? ORDER BY t",-1,&stmt,nil);guard rc == SQLITE_OK, let q=stmt else{throw fail(rc)};defer{sqlite3_finalize(q)};sqlite3_bind_double(q,1,since.timeIntervalSince1970);var result:[Sample]=[]
  while true { let step=sqlite3_step(q);if step == SQLITE_DONE {break};guard step == SQLITE_ROW,let bytes=sqlite3_column_blob(q,0) else{throw fail(step)};let size=Int(sqlite3_column_bytes(q,0));let data=Data(bytes:bytes,count:size);result.append(try JSONDecoder().decode(Sample.self,from:data)) };return result
 }
 func prune(before:Date)throws {var stmt:OpaquePointer?;let rc=sqlite3_prepare_v2(db,"DELETE FROM samples WHERE t < ?",-1,&stmt,nil);guard rc == SQLITE_OK,let q=stmt else{throw fail(rc)};defer{sqlite3_finalize(q)};sqlite3_bind_double(q,1,before.timeIntervalSince1970);let r=sqlite3_step(q);guard r == SQLITE_DONE else{throw fail(r)} }
 func clear()throws {try execute("DELETE FROM samples")}
}
