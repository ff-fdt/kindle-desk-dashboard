// Portrait dashboard rasterizer. Refresh coordinates match the device touch hitbox.
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
// Native portrait layout: 48 px outer margins, 818 px feed, 254 px sidebar.
func outline(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ radius: Double, _ gray: Double = 0.76) {
    NSColor(white:gray,alpha:1).setStroke()
    let path = NSBezierPath(roundedRect:NSRect(x:x,y:y,width:w,height:h),xRadius:radius,yRadius:radius)
    path.lineWidth = 1.5; path.stroke()
}
rect(0,0,1236,1648,1)
let now = number(state,"generated_at",Date().timeIntervalSince1970)
let weather = object("weather"), mac = object("mac"), kindle = object("kindle")
text(date(now,"HH:mm"),42,27,520,170,700,leading:170,kern:-8)
text(date(now,english ? "EEEE, d MMMM" : "M月d日  EEEE"),48,205,650,english ? 30 : 34,500,leading:45)
let city = string(weather,"city","London")
let weatherRight = 1188.0
text(city == "London" ? tr("伦敦","London") : city,748,44,440,28,500,align:"right")
let code = Int(number(weather,"code",3))
let temperature = flag(weather,"available") ? fmt(number(weather,"temperature"))+"°" : "—"
let condition = flag(weather,"available") ? (english ? descriptions[code] ?? "Unknown" : string(weather,"description")) : tr("暂无天气","Unavailable")
let conditionSize = english ? 23.0 : 26.0
let conditionWidth = min(220,width(condition,conditionSize)+2)
let temperatureWidth = width(temperature,78,600)+4
let conditionX = weatherRight-conditionWidth
let temperatureX = conditionX-18-temperatureWidth
let weatherIconX = temperatureX-20-72
icon(weatherIcon(code),weatherIconX,108,72)
text(temperature,temperatureX,96,temperatureWidth,78,600,leading:96,kern:-2)
text(condition,conditionX,126,conditionWidth,conditionSize,400,leading:36,align:"right")
let forecast = flag(weather,"available") ? "\(fmt(number(weather,"low")))° – \(fmt(number(weather,"high")))°   \(tr("降雨","Rain")) \(fmt(number(weather,"rain_percent")))%" + (flag(weather,"stale") ? tr(" · 缓存"," · cached") : "") : tr("等待天气更新","Waiting for weather")
text(forecast,748,205,440,25,400,leading:45,align:"right")
rule(48,286,1140,1.5,0.65)
rule(900,320,1,1292,0.69)
text("Codex",48,324,250,42,650,leading:54)
text(tr("系统状态","System"),934,324,254,34,600,leading:54)
rule(934,408,254,1,0.69)
let codex = object("codex")
let items = Array((codex["items"] as? [[String: Any]] ?? []).sorted { number($0,"updated_at",number($0,"at")) > number($1,"updated_at",number($1,"at")) }.prefix(4))
let running = items.filter{string($0,"status")=="running"}.count
if !items.isEmpty { text("\(running) \(tr("进行中","in progress")) · \(items.count-running) \(tr("已完成","completed"))",350,324,516,english ? 24 : 26,400,ink,leading:54,align:"right") }
let cardHeight = 281.0, cardGap = 22.0
for (index,item) in items.enumerated() {
    let top = 410 + Double(index)*(cardHeight+cardGap), active = string(item,"status")=="running"
    outline(48.75,top+0.75,816.5,cardHeight-1.5,18)
    text(date(number(item,"at"),"HH:mm"),80,top+20,200,23,400,muted,leading:36)
    let status = active ? tr("进行中","In progress") : tr("已完成","Completed")
    let labelWidth = width(status,24,550), badgeWidth = labelWidth+68, badgeX = 834-badgeWidth
    rect(badgeX,top+18,badgeWidth,42,active ? 0.10 : 0.91,16)
    if active { rect(badgeX+18,top+33,12,12,1,6) }
    else { icon("check",badgeX+14,top+25,28) }
    text(status,badgeX+46,top+18,labelWidth+4,24,550,active ? .white : ink,leading:42)
    let question = string(item,"question")
    let questionRuns = item["question_runs"] as? [[String:Any]]
    let questionLayout = MathTextLayout(question,runs:questionRuns,
        width:754,size:30,weight:600,maxHeight:54,maxLines:1,leading:42)
    let qY = top+70
    questionLayout.draw(x:80,y:qY,width:754)
    let replyY = top+128
    let reply = string(item,"reply")
    let replyLayout = MathTextLayout(reply.isEmpty ? tr("等待回复…","Waiting for a reply…") : reply,
        runs:reply.isEmpty ? nil : item["reply_runs"] as? [[String:Any]],width:754,size:27,
        maxHeight:top+cardHeight-24-replyY,maxLines:3,leading:40)
    replyLayout.draw(x:80,y:replyY,width:754)
}
if items.isEmpty {
    text(flag(codex,"available") ? tr("等待新的对话","Waiting for a conversation") : tr("Codex 暂不可用","Codex unavailable"),80,700,754,35,500,muted,lines:2)
}
func resource(_ name: String, _ percentage: Double, _ y: Double, _ detail: String) {
    text(name,934,y,152,32,600,leading:42)
    text(fmt(percentage)+"%",1092,y,96,28,550,leading:42,align:"right")
    text(detail,934,y+65,254,25,400,leading:36)
    rect(934,y+116,254,17,0.83); rect(934,y+116,254*min(100,max(0,percentage))/100,17,0.10)
    rule(934,y+182,254,1,0.70)
}
text("CPU",934,450,152,32,600,leading:42)
text(fmt(number(mac,"cpu_percent"))+"%",1092,450,96,28,550,leading:42,align:"right")
let history = Array((mac["cpu_history"] as? [Double] ?? []).suffix(32))
let step = 254.0/Double(max(1,history.count))
for (index,value) in history.enumerated() {
    let h = max(3,min(100,value)*1.2)
    rect(934+Double(index)*step,640-h,min(4,max(3,step*0.44)),h,0.10)
}
text(history.count > 1 ? tr("最近 ","Last ")+String(history.count)+tr(" 分钟"," min") : tr("正在采样","Sampling"),934,658,254,24,400,muted,leading:34)
rule(934,726,254,1,0.70)
resource(tr("内存","Memory"),number(mac,"memory_percent"),770,"\(fmt(number(mac,"memory_used_gb"),1)) / \(fmt(number(mac,"memory_total_gb"))) GB")
resource(tr("磁盘","Storage"),number(mac,"disk_percent"),1000,"\(fmt(number(mac,"disk_used_gb"))) / \(fmt(number(mac,"disk_total_gb"))) GB")
text(tr("Kindle 电量","Kindle battery"),934,1224,254,english ? 30 : 32,600,leading:44)
let battery = (kindle["battery_percent"] as? NSNumber)?.doubleValue
text(battery.map{fmt($0)+"%"} ?? "—",934,1284,184,76,600,leading:94,kern:-2)
let charging = flag(kindle,"charging")
icon(charging ? "battery-charging" : battery.map{"battery-\(max(1,min(4,Int(ceil($0/25)))))"} ?? "battery",1126,1303,62)
let observed = number(kindle,"observed_at")
let batteryDetail = battery == nil ? tr("等待读取","Waiting for Kindle") : observed == 0 || Date().timeIntervalSince1970-observed > 180 ? tr("上次读数 ","Last reading ")+date(observed,"HH:mm") : charging ? tr("正在充电","Charging") : tr("电池供电","On battery")
text(batteryDetail,934,1382,254,25,400,muted,lines:2,leading:34)
// Preserve the device's existing refresh touch rectangle.
outline(934.5,1518.5,253,57,7,0.53)
let refreshTitle = tr("刷新","Refresh"), refreshWidth = width(refreshTitle,26,500)
let refreshX = 934+(254-refreshWidth-44)/2
ctx.saveGState()
ctx.setStrokeColor(ink.cgColor); ctx.setFillColor(ink.cgColor); ctx.setLineWidth(2.4); ctx.setLineCap(.round)
let cx = refreshX+14, cy = 1547.0
for angle in [0.0,Double.pi] {
    let start = angle+0.35, end = angle+2.65
    ctx.addArc(center:CGPoint(x:cx,y:cy),radius:10,startAngle:start,endAngle:end,clockwise:false); ctx.strokePath()
    let tip = CGPoint(x:cx+10*cos(end),y:cy+10*sin(end))
    let tx = -sin(end), ty = cos(end), nx = cos(end), ny = sin(end)
    ctx.move(to:tip); ctx.addLine(to:CGPoint(x:tip.x-tx*7+nx*4,y:tip.y-ty*7+ny*4))
    ctx.addLine(to:CGPoint(x:tip.x-tx*7-nx*4,y:tip.y-ty*7-ny*4)); ctx.closePath(); ctx.fillPath()
}
ctx.restoreGState()
text(refreshTitle,refreshX+44,1529,refreshWidth+2,26,500,leading:36)
text(tr("更新 ","Updated ")+date(now,"HH:mm"),934,1580,254,21,400,muted,leading:32,align:"center")
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
