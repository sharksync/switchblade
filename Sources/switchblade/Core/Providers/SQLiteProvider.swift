//
//  SQLiteProvider.swift
//  SwiftyShark
//
//  Created by Adrian Herridge on 08/05/2019.
//

import Foundation

#if os(Linux)
import CSQLiteLinux
#else
import CSQLiteDarwin
#endif

import Dispatch

internal let SQLITE_STATIC = unsafeBitCast(0, to: sqlite3_destructor_type.self)
internal let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public class SQLiteProvider: DataProvider {
    
    public var table_alias: [String : String] = [:]
    
    var db: OpaquePointer?
    public var structure: [String:[String:DataType]] = [:]
    public var pks: [String:String] = [:]
    private var p: String?
    
    public init(path: String)  {
        p = path
    }
    
    public func open() throws {
        // create any folders up until this point as well
        let _ = sqlite3_open("\(p!)", &db);
        if db == nil {
            throw DatabaseError.Init(.UnableToCreateLocalDatabase)
        }
        sqlite3_create_function(db, "SHA512", 1, SQLITE_ANY, nil, nil, sha512step, sha512finalize)
    }
    
    public func close() throws {
        sqlite3_close(db)
        db = nil;
    }
    
    public func execute(sql: String, params:[Any?], silenceErrors: Bool) throws -> Result {
        
        let result = Result()
        
        var values: [Any?] = []
        for o in params {
            values.append(o)
        }
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, Int32(sql.utf8.count), &stmt, nil) == SQLITE_OK {
            
            bind(stmt: stmt, params: values);
            while sqlite3_step(stmt) != SQLITE_DONE {
                
            }
            
        } else {
            // error in statement
            if !silenceErrors {
                throw DatabaseError.Execute(.SyntaxError("\(String(cString: sqlite3_errmsg(db)))"))
            }
        }
        
        sqlite3_finalize(stmt)
        
        return result
        
    }
    
    let IntTypes: [Any.Type] = [Int?.self,Int.self,UInt64?.self,UInt64.self,UInt?.self,UInt.self,Int64?.self,Int64.self]
    let UUIDTypes: [Any.Type] = [UUID.self, UUID?.self]
    let NumberTypes: [Any.Type] = [Double.self, Double?.self, Float?.self]
    
    public func create<T>(_ object: T, pk: String, auto: Bool, indexes: [String]) throws where T: Codable {
        
        let mirror = Mirror(reflecting: object)
        var name = "\("\(mirror)".split(separator: " ").last!)"
        if table_alias[name] != nil {
            name = table_alias[name]!
        }
        
        // find the pk, examine the type and create the table
        for c in mirror.children {
            if c.label != nil {
                if c.label! == pk {
                    
                    let propMirror = Mirror(reflecting: c.value)
                    if propMirror.subjectType == String?.self || propMirror.subjectType == String.self {
                        _ = try self.execute(sql: "CREATE TABLE IF NOT EXISTS \(name) (\(pk) TEXT PRIMARY KEY);", params: [])
                    } else if propMirror.subjectType == UUID?.self || propMirror.subjectType == UUID.self {
                        _ = try self.execute(sql: "CREATE TABLE IF NOT EXISTS \(name) (\(pk) TEXT PRIMARY KEY);", params: [])
                    } else if propMirror.subjectType == Int?.self || propMirror.subjectType == Int.self {
                        _ = try self.execute(sql: "CREATE TABLE IF NOT EXISTS \(name) (\(pk) INTEGER PRIMARY KEY \(auto ? "AUTOINCREMENT" : ""));", params: [])
                    }
                    
                    pks[name] = pk
                    structure[name] = [:]
                }
            }
        }
        
        for c in mirror.children {
            
            if c.label != nil {
                let propMirror = Mirror(reflecting: c.value)
                if propMirror.subjectType == String?.self || propMirror.subjectType == String.self {
                    _ = try self.execute(sql: "ALTER TABLE \(name) ADD COLUMN \(c.label!) TEXT", params: [], silenceErrors:true)
                    structure[name]!["\(c.label!)"] = .String
                } else if propMirror.subjectType == Int?.self || propMirror.subjectType == UInt64?.self || propMirror.subjectType == UInt?.self || propMirror.subjectType == Int64?.self || propMirror.subjectType == Int.self || propMirror.subjectType == UInt64.self || propMirror.subjectType == UInt.self || propMirror.subjectType == Int64.self {
                    _ = try self.execute(sql: "ALTER TABLE \(name) ADD COLUMN \(c.label!) INTEGER", params: [], silenceErrors:true)
                    structure[name]!["\(c.label!)"] = .Int
                } else if propMirror.subjectType == Double?.self || propMirror.subjectType == Double.self || propMirror.subjectType == Float?.self || propMirror.subjectType == Float.self {
                    _ = try self.execute(sql: "ALTER TABLE \(name) ADD COLUMN \(c.label!) REAL", params: [], silenceErrors:true)
                    structure[name]!["\(c.label!)"] = .Double
                } else if propMirror.subjectType == Data?.self || propMirror.subjectType == Data.self {
                    _ = try self.execute(sql: "ALTER TABLE \(name) ADD COLUMN \(c.label!) BLOB", params: [], silenceErrors:true)
                    structure[name]!["\(c.label!)"] = .Blob
                } else if propMirror.subjectType == UUID?.self || propMirror.subjectType == UUID.self {
                    _ = try self.execute(sql: "ALTER TABLE \(name) ADD COLUMN \(c.label!) TEXT", params: [], silenceErrors:true)
                    structure[name]!["\(c.label!)"] = .UUID
                } else {
                    // unsupported, could be a custom type.  Gotta go with string.
                    _ = try self.execute(sql: "ALTER TABLE \(name) ADD COLUMN \(c.label!) TEXT", params: [], silenceErrors:true)
                    structure[name]!["\(c.label!)"] = .Interpreted
                }
            }
            
        }
        
        for i in indexes {
            _ = try self.execute(sql: "CREATE INDEX IF NOT EXISTS idx_\(name)_\(i.replacingOccurrences(of: ",", with: "_")) ON \(name) (\(i));", params: [], silenceErrors:true)
        }
        
    }
    
    public func execute(sql: String, params:[Any?]) throws -> Result {
        
        return try execute(sql: sql, params: params, silenceErrors: false)
        
    }
    
    public func query(sql: String, params:[Any?]) -> Result {
        
        let result = Result()
        var results: [[String:Any?]] = []
        
        var values: [Any?] = []
        for o in params {
            values.append(o)
        }
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, Int32(sql.utf8.count), &stmt, nil) == SQLITE_OK {
            bind(stmt: stmt, params: values);
            while sqlite3_step(stmt) == SQLITE_ROW {
                
                var rowData: Record = [:]
                let columns = sqlite3_column_count(stmt)
                if columns > 0 {
                    for i in 0...Int(columns-1) {
                        
                        let columnName = String.init(cString: sqlite3_column_name(stmt, Int32(i)))
                        let tableName = String.init(cString: sqlite3_column_table_name(stmt, Int32(i)))
                        var value: Any?
                        
                        switch sqlite3_column_type(stmt, Int32(i)) {
                        case SQLITE_INTEGER:
                            value = Int(sqlite3_column_int64(stmt, Int32(i)))
                        case SQLITE_FLOAT:
                            value = Double(sqlite3_column_double(stmt, Int32(i)))
                        case SQLITE_TEXT:
                            value = String.init(cString:sqlite3_column_text(stmt, Int32(i)))
                        case SQLITE_BLOB:
                            let d = Data(bytes: sqlite3_column_blob(stmt, Int32(i)), count: Int(sqlite3_column_bytes(stmt, Int32(i))))
                            value = d
                            // inspect this to see if it is in fact a uuid
                            if structure[tableName]![columnName]! == .UUID {
                                let u = UUID(uuid: (d.bytes[0],d.bytes[1],d.bytes[2],d.bytes[3],d.bytes[4],d.bytes[5],d.bytes[6],d.bytes[7],d.bytes[8],d.bytes[9],d.bytes[10],d.bytes[11],d.bytes[12],d.bytes[13],d.bytes[14],d.bytes[15]))
                                value = u
                            }
                        case SQLITE_NULL:
                            value = nil
                        default:
                            value = nil
                            break;
                        }
                        
                        rowData[columnName] = value
                        
                    }
                }
                results.append(rowData)
                
            }
        } else {
            // error in statement
            result.error = DatabaseError.Query(.SyntaxError("\(String(cString: sqlite3_errmsg(db)))"))
        }
        
        result.results = results
        
        sqlite3_finalize(stmt)
        
        return result
        
    }
    
    public func delete<T>(_ object: T, completion: ((Bool, DatabaseError?) -> Void)?) where T : Decodable, T : Encodable {
        
        let mirror = Mirror(reflecting: object)
        var name = "\("\(mirror)".split(separator: " ").last!)"
        if table_alias[name] != nil {
            name = table_alias[name]!
        }
        let n = name
        let pk = pks[n]!
        var pkValue: Any?
        
        let types: [Any.Type] = [String?.self, String.self,Int?.self,Int.self,UInt64?.self,UInt64.self,UInt?.self,UInt.self,Int64?.self,Int64.self,Double?.self,Double.self,Data?.self,Data.self,UUID.self,UUID?.self]
        
        // find the pk, examine the type and create the table
        for c in mirror.children {
            if c.label != nil {
                let propMirror = Mirror(reflecting: c.value)
                for t in types {
                    if t == propMirror.subjectType {
                        
                        if pk.lowercased() == c.label!.lowercased() {
                            // this is the pk
                            pkValue = unwrap(c.value)
                        }
                        
                    }
                }
            }
        }
        
        let r = try? execute(sql: "DELETE FROM \(n) WHERE \(pk) = ?", params: [pkValue])
        
        if r == nil {
            
            completion?(false, .Unknown)
            
        } else {
            if r!.error == nil {
                completion?(true, nil)
            } else {
                completion?(false, r!.error)
            }
        }
        
    }
    
    public func delete<T>(_ object: T, parameters: [param], completion: ((Bool, DatabaseError?) -> Void)?) where T : Decodable, T : Encodable {
        
        let mirror = Mirror(reflecting: object)
        var name = "\("\(mirror)".split(separator: " ").last!)"
        if table_alias[name] != nil {
            name = table_alias[name]!
        }
        var params: [Any?] = []
        
        // build the conditionals
        var sql = "DELETE FROM \(name) "
        
        // loop to see if there are any where conditions
        var foundWhere = false
        for p in parameters {
            switch p {
            case .where(_, _, _):
                foundWhere = true
                break;
            default:
                break
            }
        }
        
        if foundWhere {
            sql += " WHERE "
            var wheres: [String] = []
            for p in parameters {
                switch p {
                case .where(let column, let op, let param):
                    switch op {
                    case .equals:
                        wheres.append("\(column) = ?")
                        params.append(param)
                    case .greater:
                        wheres.append("\(column) > ?")
                        params.append(param)
                    case .isnotnull:
                        wheres.append("\(column) IS NOT NULL")
                    case .isnull:
                        wheres.append("\(column) IS NULL")
                    case .less:
                        wheres.append("\(column) < ?")
                        params.append(param)
                    }
                    break;
                default:
                    break
                }
            }
            sql += wheres.joined(separator: " AND ")
        }
        
        // loop to see if there are any orderby conditions
        var foundOrder = false
        for p in parameters {
            switch p {
            case .order(_):
                foundOrder = true
                break;
            default:
                break
            }
        }
        
        if foundOrder {
            sql += " ORDER BY "
            for p in parameters {
                switch p {
                case .order(let o):
                    sql += o
                    break;
                default:
                    break
                }
            }
        }
        
        // loop to see if there are any limit conditions
        var foundLimit = false
        for p in parameters {
            switch p {
            case .limit(_):
                foundLimit = true
                break;
            default:
                break
            }
        }
        
        if foundLimit {
            sql += " LIMIT "
            for p in parameters {
                switch p {
                case .limit(let o):
                    sql += "\(o)"
                    break;
                default:
                    break
                }
            }
        }
        
        let r = try? execute(sql: sql, params: params)
        if r == nil {
            completion?(false, .Unknown)
        } else {
            if r!.error == nil {
                completion?(true, nil)
            } else {
                completion?(false, r!.error)
            }
        }
    }
    
    public func put<T>(_ object: T, completion: ((Bool, DatabaseError?) -> Void)?) where T : Decodable, T : Encodable {
        
        let mirror = Mirror(reflecting: object)
        var name = "\("\(mirror)".split(separator: " ").last!)"
        if table_alias[name] != nil {
            name = table_alias[name]!
        }
        
        var placeholders: [String] = []
        var columns: [String] = []
        var params: [Any?] = []
        let types: [Any.Type] = [String?.self, String.self,Int?.self,Int.self,UInt64?.self,UInt64.self,UInt?.self,UInt.self,Int64?.self,Int64.self,Double?.self,Double.self,Data?.self,Data.self,UUID.self,UUID?.self]
        
        // find the pk, examine the type and create the table
        for c in mirror.children {
            if c.label != nil {
                let propMirror = Mirror(reflecting: c.value)
                var found = false
                for t in types {
                    if t == propMirror.subjectType {
                        placeholders.append("?")
                        params.append(unwrap(c.value))
                        columns.append(c.label!)
                        found = true
                    }
                }
                if !found {
                    // format this into a string
                    if unwrap(c.value) == nil {
                        placeholders.append("?")
                        params.append(unwrap(c.value))
                        columns.append(c.label!)
                    } else {
                        placeholders.append("?")
                        params.append("\(unwrap(c.value)!)")
                        columns.append(c.label!)
                    }
                }
            }
        }
        
        let r = try? execute(sql: "INSERT OR REPLACE INTO \(name) (\(columns.joined(separator: ","))) VALUES (\(placeholders.joined(separator: ",")))", params: params)
        if r == nil {
            completion?(false, .Unknown)
        } else {
            if r!.error == nil {
                completion?(true, nil)
            } else {
                completion?(false, r!.error)
            }
        }
    }
    
    public func query<T>(_ object: T, parameters: [param], completion: (([T], DatabaseError?) -> Void)?) where T : Decodable, T : Encodable {
        
        let mirror = Mirror(reflecting: object)
        var name = "\("\(mirror)".split(separator: " ").last!)"
        if table_alias[name] != nil {
            name = table_alias[name]!
        }
        
        var params: [Any?] = []
        
        // build the conditionals
        var sql = "SELECT * FROM \(name) "
        
        // loop to see if there are any where conditions
        var foundWhere = false
        for p in parameters {
            switch p {
            case .where(_, _, _):
                foundWhere = true
                break;
            default:
                break
            }
        }
        
        if foundWhere {
            sql += " WHERE "
            var wheres: [String] = []
            for p in parameters {
                switch p {
                case .where(let column, let op, let param):
                    switch op {
                    case .equals:
                        wheres.append("\(column) = ?")
                        params.append(param)
                    case .greater:
                        wheres.append("\(column) > ?")
                        params.append(param)
                    case .isnotnull:
                        wheres.append("\(column) IS NOT NULL")
                    case .isnull:
                        wheres.append("\(column) IS NULL")
                    case .less:
                        wheres.append("\(column) < ?")
                        params.append(param)
                    }
                    break;
                default:
                    break
                }
            }
            sql += wheres.joined(separator: " AND ")
        }
        
        // loop to see if there are any orderby conditions
        var foundOrder = false
        for p in parameters {
            switch p {
            case .order(_):
                foundOrder = true
                break;
            default:
                break
            }
        }
        
        if foundOrder {
            sql += " ORDER BY "
            for p in parameters {
                switch p {
                case .order(let o):
                    sql += o
                    break;
                default:
                    break
                }
            }
        }
        
        // loop to see if there are any limit conditions
        var foundLimit = false
        for p in parameters {
            switch p {
            case .limit(_):
                foundLimit = true
                break;
            default:
                break
            }
        }
        
        if foundLimit {
            sql += " LIMIT "
            for p in parameters {
                switch p {
                case .limit(let o):
                    sql += "\(o)"
                    break;
                default:
                    break
                }
            }
        }
        
        let r = query(sql: sql, params: params)
        if r.error != nil {
            completion?([], r.error)
        }
        
        var results: [T] = []
        
        
        for record in r.results {
            
            let decoder = JSONDecoder()
            decoder.dataDecodingStrategy = .base64
            
            var row: [String] = []
            
            for k in record.keys {
                
                if let value = record[k]! {
                    
                    if let d = value as? Data {
                        row.append("\"\(k)\" : \"\(d.base64EncodedString())\"")
                    } else if let d = value as? Double {
                        row.append("\"\(k)\" : \(d)")
                    } else if let f = value as? Float {
                        row.append("\"\(k)\" : \(f)")
                    } else if let i = value as? Int {
                        row.append("\"\(k)\" : \(i)")
                    } else if let s = value as? String {
                        row.append("\"\(k)\" : \"\(s)\"")
                    } else if let u = value as? UUID {
                        row.append("\"\(k)\" : \"\(u.uuidString)\"")
                    } else {
                        row.append("\"\(k)\" : \"\(value)\"")
                    }
                    
                } else {
                    // null
                    row.append("\"\(k)\" : null")
                }
                
            }
            
            let jsonString = "{\(row.joined(separator: ","))}"
            
            do {
                let rowObject: T = try decoder.decode(T.self, from: Data(Array(jsonString.utf8)))
                results.append(rowObject)
            } catch {
                print("JSON causing the issue: \n\n\(jsonString)\n")
                print(error)
            }
            
            
        }
        
        completion?(results, nil)
        
    }
    
    private func bind(stmt: OpaquePointer?, params:[Any?]) {
        
        var paramCount = sqlite3_bind_parameter_count(stmt)
        let passedIn = params.count
        
        if(Int(paramCount) != passedIn) {
            // error
        }
        
        paramCount = 1;
        
        for v in params {
            
            if v != nil {
                
                if let s = v! as? String {
                    sqlite3_bind_text(stmt,paramCount,s,Int32(s.count),SQLITE_TRANSIENT)
                } else if let u = v! as? UUID {
                    sqlite3_bind_blob(stmt, paramCount, u.asUInt8Array(), Int32(u.asUInt8Array().count), SQLITE_TRANSIENT)
                } else if let b = v! as? Data {
                    sqlite3_bind_blob(stmt, paramCount,b.bytes,Int32(b.count), SQLITE_TRANSIENT)
                } else if let d = v! as? Double {
                    sqlite3_bind_double(stmt, paramCount, d)
                } else if let f = v! as? Float {
                    sqlite3_bind_double(stmt, paramCount, NSNumber(value: f).doubleValue)
                } else if let i = v! as? Int {
                    sqlite3_bind_int64(stmt, paramCount, Int64(i))
                } else if let i = v! as? Int64 {
                    sqlite3_bind_int64(stmt, paramCount, i)
                } else {
                    let s = "\(v!)"
                    sqlite3_bind_text(stmt, paramCount, s,Int32(s.count) , SQLITE_TRANSIENT)
                }
                
            } else {
                sqlite3_bind_null(stmt, paramCount)
            }
            
            
            
            paramCount += 1
            
        }
        
    }
    
}

extension UUID{
    public func asUInt8Array() -> [UInt8] {
        let (u1,u2,u3,u4,u5,u6,u7,u8,u9,u10,u11,u12,u13,u14,u15,u16) = self.uuid
        return [u1,u2,u3,u4,u5,u6,u7,u8,u9,u10,u11,u12,u13,u14,u15,u16]
    }
    public func asData() -> Data {
        return Data(self.asUInt8Array())
    }
}

extension Data {
    var bytes : [UInt8]{
        return [UInt8](self)
    }
}
