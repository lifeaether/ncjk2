import Foundation

func usage() {
    print( "ncjk: usage: ncjk channel" )
}

func getInfo( channel: String ) -> Dictionary<String, String> {
    var parameter: Dictionary<String, String> = [:]
    if let url = URL.init(string: "http://jk.nicovideo.jp/api/getflv?v=\(channel)") {
        if let data = try? Data.init(contentsOf: url) {
            if let info = String.init(data: data, encoding: String.Encoding.utf8) {
                let scanner = Scanner.init(string: info)
                while !scanner.isAtEnd {
                    var key: NSString? = nil
                    var value: NSString? = nil
                    if !scanner.scanUpTo("=", into: &key) {
                        break
                    }
                    if !scanner.scanString("=", into: nil) {
                        break
                    }
                    if !scanner.scanUpTo("&", into: &value) {
                        break
                    }
                    parameter[key as! String] = value as? String
                    if !scanner.scanString("&", into: nil) {
                        break
                    }
                }
            }
        }
    }
    return parameter
}

var running = true
signal( SIGINT, { ( sig: Int32 ) in
    print( "" )
    running = false
} )

if CommandLine.arguments.count != 2 {
    usage()
    exit( EXIT_FAILURE )
}

let parameter = getInfo(channel: CommandLine.arguments[1])
if parameter["ms"] == nil || parameter["ms_port"] == nil || parameter["thread_id"] == nil {
    print( "ncjk: Failed to get infomation." )
    exit( EXIT_FAILURE )
}

let ms = parameter["ms"]!
let port = Int( parameter["ms_port"]! )!
let thread = parameter["thread_id"]!

var pinStream: InputStream? = nil
var poutStream: OutputStream? = nil
Stream.getStreamsToHost(withName: ms, port: port, inputStream: &pinStream, outputStream: &poutStream)
if pinStream == nil || poutStream == nil {
    print( "ncjk: Failed to create stream." )
    exit( EXIT_FAILURE )
}

let inStream = pinStream!
let outStream = poutStream!

inStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
outStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
inStream.open()
outStream.open()

do {
    var data = "<thread thread=\"\(thread)\" res_from=\"0\" version=\"20061206\" />".data(using: String.Encoding.utf8)!
    data.append(0);
    data.withUnsafeBytes( { (bytes: UnsafePointer<UInt8>) -> Void in
        if outStream.write(bytes, maxLength: data.count) != data.count {
            print( "ncjk: Failed to write stream." )
            exit( EXIT_FAILURE )
        }
    })
}

var receivedData: Data = Data.init()
while running {
    if inStream.hasBytesAvailable {
        var data = Data.init(count: 1024)
        data.withUnsafeMutableBytes( {(bytes: UnsafeMutablePointer<UInt8>) -> Void in
            let count = inStream.read(bytes, maxLength: data.count)
            if count < 0 {
                print( "ncjk: Failed to read stream." )
                running = false
            } else if count == 0 {
                running = false
            } else {
                receivedData.append(data.subdata(in: 0..<count ))
            }
        })
        while receivedData.count > 0 {
            if let index = receivedData.index(of: 0) {
                let data = receivedData.subdata(in: 0 ..< index)
                if let xml = String.init(data: data, encoding: String.Encoding.utf8) {
                    if let element = try? XMLElement.init(xmlString: xml) {
                        if element.name == "chat" {
                            if let string = element.stringValue {
                                print( string )
                            }
                        }
                    }
                }
                receivedData.removeSubrange( 0 ... index )
            } else {
                break
            }
        }
    } else {
        RunLoop.current.run(until: Date.init(timeIntervalSinceNow: 0.1))
    }
}

inStream.close()
outStream.close()

exit( EXIT_SUCCESS )
