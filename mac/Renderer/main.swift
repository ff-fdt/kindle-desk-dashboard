// Portrait dashboard rasterizer. Coordinates match panel/panel.css and the device refresh hitbox.
import AppKit
import CoreText
import ImageIO

let request = try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as! [String: Any]
let state = request["state"] as? [String: Any] ?? [:]
let ui = request["ui"] as? [String: Any] ?? [:]
let english = ui["language"] as? String == "en"
let assets = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("panel/assets")
func tr(_ zh: String, _ en: String) -> String { english ? en : zh }
func object(_ key: String) -> [String: Any] { state[key] as? [String: Any] ?? [:] }
func number(_ d: [String: Any], _ key: String, _ fallback: Double = 0) -> Double { (d[key] as? NSNumber)?.doubleValue ?? fallback }
func string(_ d: [String: Any], _ key: String, _ fallback: String = "") -> String { d[key] as? String ?? fallback }
func flag(_ d: [String: Any], _ key: String) -> Bool { d[key] as? Bool ?? false }
func fmt(_ n: Double, _ decimals: Int = 0) -> String {
    let f = NumberFormatter(); f.locale = Locale(identifier: "en_GB")
    f.numberStyle = .decimal; f.minimumFractionDigits = decimals; f.maximumFractionDigits = decimals
    return f.string(from: NSNumber(value: n.isFinite ? n : 0)) ?? "—"
}
let zone = TimeZone(identifier: string(state, "timezone", "Europe/London")) ?? .current
func date(_ timestamp: Double, _ format: String) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: english ? "en_GB" : "zh_CN")
    f.timeZone = zone; f.dateFormat = format; return f.string(from: Date(timeIntervalSince1970: timestamp))
}
let ink = NSColor(white: 0.078, alpha: 1), muted = NSColor(white: 0.384, alpha: 1)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1236, pixelsHigh: 1648,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
let ctx = graphics.cgContext
ctx.translateBy(x: 0, y: 1648); ctx.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)
func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ gray: Double, _ radius: Double = 0) {
    NSColor(white: gray, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}
func rule(_ x: Double, _ y: Double, _ w: Double, _ h: Double = 1, _ gray: Double = 0.78) { rect(x,y,w,h,gray) }
func font(_ size: Double, _ weight: Double) -> NSFont {
    let name = weight >= 600 ? "HelveticaNeue-Bold" : weight >= 500 ? "HelveticaNeue-Medium" : "HelveticaNeue"
    return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
}
func attrs(_ size: Double, _ weight: Double, _ color: NSColor, _ kern: Double) -> [NSAttributedString.Key: Any] {
    [.font: font(size,weight), .foregroundColor: color, .kern: kern]
}
func width(_ s: String, _ size: Double, _ weight: Double = 400) -> Double {
    CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string:s,attributes:attrs(size,weight,ink,0))),nil,nil,nil)
}
@discardableResult
func text(_ s: String, _ x: Double, _ y: Double, _ w: Double, _ size: Double,
          _ weight: Double = 400, _ color: NSColor = ink, lines: Int = 1,
          leading: Double? = nil, align: String = "left", kern: Double = 0) -> Int {
    if s.isEmpty || w <= 0 || lines <= 0 { return 0 }
    let attributes = attrs(size,weight,color,kern), f = font(size,weight)
    let source = NSAttributedString(string:s, attributes:attributes)
    let typesetter = CTTypesetterCreateWithAttributedString(source)
    let height = leading ?? size * 1.3
    var offset = 0, count = 0
    while offset < source.length && count < lines {
        let length = max(1,CTTypesetterSuggestLineBreak(typesetter,offset,w))
        var line = CTTypesetterCreateLine(typesetter,CFRange(location:offset,length:min(length,source.length-offset)))
        if count == lines-1 && offset+length < source.length {
            let tail = source.attributedSubstring(from:NSRange(location:offset,length:source.length-offset)).mutableCopy() as! NSMutableAttributedString
            // A single final line with an ellipsis, including for embedded newlines.
            tail.mutableString.replaceOccurrences(of:"\n",with:" ",range:NSRange(location:0,length:tail.length))
            let full = CTLineCreateWithAttributedString(tail)
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string:"…",attributes:attributes))
            line = CTLineCreateTruncatedLine(full,w,.end,ellipsis) ?? line
        }
        let measured = CTLineGetTypographicBounds(line,nil,nil,nil)
        let dx = align == "right" ? max(0,w-measured) : align == "center" ? max(0,(w-measured)/2) : 0
        let baseline = y + Double(count)*height + (height-Double(f.ascender-f.descender))/2 + Double(f.ascender)
        ctx.saveGState(); ctx.translateBy(x:x+dx,y:baseline); ctx.scaleBy(x:1,y:-1)
        ctx.textMatrix = .identity; ctx.textPosition = .zero; CTLineDraw(line,ctx); ctx.restoreGState()
        offset += length; count += 1
    }
    return count
}
func icon(_ name: String, _ x: Double, _ y: Double, _ size: Double, white: Bool = false) {
    let url = assets.appendingPathComponent(name+".svg")
    let image: NSImage?
    if white, let svg = try? String(contentsOf:url, encoding:.utf8) {
        image = NSImage(data:Data(svg.replacingOccurrences(of:"currentColor",with:"#ffffff").utf8))
    } else { image = NSImage(contentsOf:url) }
    guard let image = image else { return }
    image.draw(in:NSRect(x:x,y:y,width:size,height:size),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
}
func weatherIcon(_ code: Int) -> String {
    if code == 0 { return "sun" }; if code < 4 { return "cloud" }; if code < 50 { return "mist" }
    if code >= 95 { return "cloud-storm" }; if (71...77).contains(code) || code == 85 || code == 86 { return "cloud-snow" }
    return "cloud-rain"
}
let descriptions = [0:"Clear",1:"Mostly clear",2:"Partly cloudy",3:"Overcast",45:"Fog",48:"Rime fog",51:"Light drizzle",53:"Drizzle",55:"Heavy drizzle",56:"Freezing drizzle",57:"Freezing drizzle",61:"Light rain",63:"Rain",65:"Heavy rain",66:"Freezing rain",67:"Freezing rain",71:"Light snow",73:"Snow",75:"Heavy snow",77:"Snow grains",80:"Showers",81:"Showers",82:"Heavy showers",85:"Snow showers",86:"Snow showers",95:"Thunderstorm",96:"Thunderstorm",99:"Thunderstorm"]
rect(0,0,1236,1648,1)
let now = number(state,"generated_at",Date().timeIntervalSince1970)
text(date(now,"HH:mm"),42,40,405,166,700,leading:154.38,kern:-9)
text(date(now,english ? "EEEE, d MMMM" : "M月d日  EEEE"),48,213,402,english ? 26 : 29,500)
rule(450,53,1,182,0.67); rule(832,53,1,182,0.67); rule(48,273,1140,1,0.67)
let weather = object("weather"), mac = object("mac"), kindle = object("kindle")
let city = string(weather,"city","London")
text(city == "London" ? tr("伦敦","London") : city,485,55,315,27,500)
let code = Int(number(weather,"code",3))
icon(weatherIcon(code),485,113,68)
let temperature = flag(weather,"available") ? fmt(number(weather,"temperature"))+"°" : "—"
text(temperature,567,111,110,67,600,leading:83,kern:-2)
text(flag(weather,"available") ? (english ? descriptions[code] ?? "Unknown" : string(weather,"description")) : tr("天气暂不可用","Weather unavailable"), 678,130,149,english ? 20 : 25)
let forecast = flag(weather,"available") ? "\(fmt(number(weather,"low")))° – \(fmt(number(weather,"high")))°　\(tr("降雨","Rain")) \(fmt(number(weather,"rain_percent")))%" + (flag(weather,"stale") ? tr(" · 缓存"," · cached") : "") : tr("等待天气更新","Waiting for weather")
text(forecast,485,202,340,23)
icon("device-laptop",865,83,61)
text(string(mac,"name","Mac"),944,80,244,26,600,leading:36.4)
text(string(mac,"chip","macOS"),944,125,244,21,400,muted)
rule(900,304,1,1308,0.67); rule(48,367,818,1,0.6); rule(934,367,254,1,0.6)
text("Codex",48,304,250,35,650)
text(tr("系统状态","System"),934,304,254,29,600)
let codex = object("codex")
let items = Array((codex["items"] as? [[String: Any]] ?? []).sorted { number($0,"updated_at",number($0,"at")) > number($1,"updated_at",number($1,"at")) }.prefix(3))
let running = items.filter{string($0,"status")=="running"}.count
if !items.isEmpty { text("\(running) \(tr("进行中","in progress")) · \(items.count-running) \(tr("已完成","completed"))",400,313,466,english ? 20 : 21,400,ink,align:"right") }
let rowHeight = (1612.0-368.0)/3
for (index,item) in items.enumerated() {
    let top = 368 + Double(index)*rowHeight, active = string(item,"status")=="running"
    let status = active ? tr("进行中","In progress") : tr("已完成","Completed")
    text(date(number(item,"at"),"HH:mm"),48,top+23,200,21,400,muted,leading:31)
    let labelWidth = width(status,20,550), badgeWidth = labelWidth + (active ? 48 : 28)
    let badgeX = 866-badgeWidth
    if active { rect(badgeX,top+23,badgeWidth,31,0.1,4) }
    icon(active ? "loader" : "check",badgeX+(active ? 12 : 0),top+(active ? 29.5 : 26.5),active ? 18 : 22,white:active)
    text(status,badgeX+(active ? 36 : 28),top+23,labelWidth+1,20,550,active ? .white : ink,leading:31)
    let question = string(item,"question")
    let questionLayout = MathTextLayout(question,runs:item["question_runs"] as? [[String:Any]],
        width:788,size:27,weight:500,maxHeight:101,maxLines:2,leading:40.5)
    let qY = top+67, qHeight = max(40.5,questionLayout.height)+22
    rect(48,qY,818,qHeight,0.945,6)
    questionLayout.draw(x:63,y:qY+11,width:788)
    let labelY = qY+qHeight+16
    text("Codex"+(active ? "" : " · "+date(number(item,"updated_at",number(item,"at")),"HH:mm")),48,labelY,818,20,400,muted,leading:26)
    let replyY = labelY+32, available = top+rowHeight-22-replyY
    let reply = string(item,"reply")
    let replyLayout = MathTextLayout(reply.isEmpty ? tr("等待回复…","Waiting for a reply…") : reply,
        runs:reply.isEmpty ? nil : item["reply_runs"] as? [[String:Any]],width:818,size:25,
        maxHeight:available,leading:39.75)
    replyLayout.draw(x:48,y:replyY,width:818)
    if index < 2 { rule(48,top+rowHeight-1,818) }
}
if items.isEmpty {
    text(flag(codex,"available") ? tr("等待新的对话","Waiting for a conversation") : tr("Codex 暂不可用","Codex unavailable"),78,800,758,35,500,muted,lines:2)
}
func resource(_ name: String, _ percentage: Double, _ y: Double, _ detail: String) {
    text(name,934,y,180,27,600); text(fmt(percentage)+"%",1090,y+2,98,25,550,align:"right")
    text(detail,934,y+50,254,22)
    rect(934,y+96,254,12,0.87,2); rect(934,y+96,254*min(100,max(0,percentage))/100,12,0.13,2)
    rule(934,y+147,254)
}
text("CPU",934,398,160,27,600);text(fmt(number(mac,"cpu_percent"))+"%",1090,400,98,25,550,align:"right")
let history = Array((mac["cpu_history"] as? [Double] ?? []).suffix(32))
for (index,value) in history.enumerated() {
    let h = max(2,min(100,value));rect(1188-Double(history.count)*8+Double(index)*8,560-h,3,h,0.145)
}
text(history.count > 1 ? tr("最近 ","Last ")+String(history.count)+tr(" 分钟"," min") : tr("正在采样","Sampling"),934,571,254,18,400,muted)
rule(934,628,254)
resource(tr("内存","Memory"),number(mac,"memory_percent"),659,"\(fmt(number(mac,"memory_used_gb"),1)) / \(fmt(number(mac,"memory_total_gb"))) GB")
resource(tr("磁盘","Storage"),number(mac,"disk_percent"),840,"\(fmt(number(mac,"disk_used_gb"))) / \(fmt(number(mac,"disk_total_gb"))) GB")
text(tr("Kindle 电量","Kindle battery"),934,1060,254,27,600)
let battery = (kindle["battery_percent"] as? NSNumber)?.doubleValue
text(battery.map{fmt($0)+"%"} ?? "—",934,1113,193,63,550,leading:81.9,kern:-2.5)
let charging = flag(kindle,"charging")
icon(charging ? "battery-charging" : battery.map{"battery-\(max(1,min(4,Int(ceil($0/25)))))"} ?? "battery",1121,1120,67)
let observed = number(kindle,"observed_at")
let batteryDetail = battery == nil ? tr("等待读取","Waiting for Kindle") : observed == 0 || Date().timeIntervalSince1970-observed > 180 ? tr("上次读数 ","Last reading ")+date(observed,"HH:mm") : charging ? tr("正在充电","Charging") : tr("电池供电","On battery")
text(batteryDetail,934,1200,254,21,400,muted,lines:2,leading:33.6)
NSColor(white:0.53,alpha:1).setStroke();let button = NSBezierPath(roundedRect:NSRect(x:934.5,y:1518.5,width:253,height:57),xRadius:5,yRadius:5);button.lineWidth=1;button.stroke()
text(tr("刷新","Refresh"),934,1529,254,22,500,align:"center")
text(tr("更新 ","Updated ")+date(now,"HH:mm"),934,1580,254,18,400,muted,leading:32.4)
// Write 16 grayscale levels directly; no browser or second image-conversion process.
let rgba = bitmap.bitmapData!
var grayscale = Data(count:1236*1648)
grayscale.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
    let pixels = raw.bindMemory(to:UInt8.self)
    for y in 0..<1648 {
        for x in 0..<1236 {
            let offset = y*bitmap.bytesPerRow+x*4
            let gray = (Int(rgba[offset])*77 + Int(rgba[offset+1])*150 + Int(rgba[offset+2])*29 + 128) >> 8
            pixels[y*1236+x] = UInt8(min(15,(gray+8)/17)*17)
        }
    }
}
let provider = CGDataProvider(data:grayscale as CFData)!
let image = CGImage(width:1236,height:1648,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:1236,
    space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:provider,
    decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
let png = NSMutableData()
let destination = CGImageDestinationCreateWithData(png,"public.png" as CFString,1,nil)!
CGImageDestinationAddImage(destination,image,nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
if ProcessInfo.processInfo.environment["KINDLE_DESK_RENDER_STATS"] == "1" {
    let report = "KINDLE_DESK_MATH_STATS {\"rendered\":\(mathRendered),\"fallback\":\(mathAttempts-mathRendered)}\n"
    FileHandle.standardError.write(Data(report.utf8))
}
FileHandle.standardOutput.write(png as Data)
