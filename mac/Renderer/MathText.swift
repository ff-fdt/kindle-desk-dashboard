import AppKit
import CoreText
import SwiftMath

var mathAttempts = 0
var mathRendered = 0

private let mathKey = NSAttributedString.Key("KindleDeskMath")
private let displayKey = NSAttributedString.Key("KindleDeskDisplayMath")

private final class FormulaGlyph {
    let image: NSImage
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    init(image: NSImage, ascent: CGFloat, descent: CGFloat, width: CGFloat, maxHeight: CGFloat) {
        let scale = min(1, width / max(1,image.size.width), maxHeight / max(1,image.size.height))
        self.image = image; self.width = image.size.width * scale
        self.ascent = (ascent + max(0,image.size.height-ascent-descent)/2) * scale
        self.descent = image.size.height * scale - self.ascent
    }
}

private func formula(_ latex: String, display: Bool, size: Double, width: Double, maxHeight: Double) -> FormulaGlyph? {
    mathAttempts += 1
    guard !latex.isEmpty, latex.count <= 2048 else { return nil }
    var depth = 0
    for c in latex {
        if c == "{" { depth += 1 }; if c == "}" { depth -= 1 }
        if depth > 48 { return nil }
    }
    var equation = MathImage(latex:latex,fontSize:size,textColor:ink,
                             labelMode:display ? .display : .text,textAlignment:.left)
    let (error,image,layout) = equation.asImage()
    guard error == nil, let image = image, let layout = layout,
          image.size.width.isFinite, image.size.height.isFinite,
          image.size.width > 0, image.size.height > 0 else { return nil }
    mathRendered += 1
    return FormulaGlyph(image:image,ascent:layout.ascent,descent:layout.descent,width:width,maxHeight:maxHeight)
}

private func attachment(_ glyph: FormulaGlyph, attributes: [NSAttributedString.Key: Any], display: Bool) -> NSAttributedString {
    let pointer = Unmanaged.passRetained(glyph).toOpaque()
    var callbacks = CTRunDelegateCallbacks(version:kCTRunDelegateVersion1,
        dealloc: { pointer in Unmanaged<FormulaGlyph>.fromOpaque(pointer).release() },
        getAscent: { Unmanaged<FormulaGlyph>.fromOpaque($0).takeUnretainedValue().ascent },
        getDescent: { Unmanaged<FormulaGlyph>.fromOpaque($0).takeUnretainedValue().descent },
        getWidth: { Unmanaged<FormulaGlyph>.fromOpaque($0).takeUnretainedValue().width })
    let delegate = CTRunDelegateCreate(&callbacks,pointer)!
    var values = attributes
    values[NSAttributedString.Key(kCTRunDelegateAttributeName as String)] = delegate
    values[mathKey] = glyph; values[displayKey] = display
    // The image supplies the visible glyph; CoreText reserves its exact metrics.
    values[.foregroundColor] = NSColor.clear
    return NSAttributedString(string:"\u{fffc}",attributes:values)
}

struct MathTextLayout {
    struct Line {
        let text: CTLine
        let ascent: CGFloat
        let descent: CGFloat
        let height: CGFloat
        let center: Bool
    }
    var lines: [Line] = []
    var height: Double { lines.reduce(0) { $0 + $1.height } }

    init(_ raw: String, runs: [[String: Any]]?, width: Double, size: Double, weight: Double = 400,
         maxHeight: Double, maxLines: Int = 100, leading: Double) {
        let values = attrs(size,weight,ink,0)
        let source = NSMutableAttributedString(string:"")
        var afterDisplay = false
        for run in runs ?? [["kind":"text","text":raw]] {
            let content = run["text"] as? String ?? ""
            let display = run["display"] as? Bool ?? false
            if run["kind"] as? String == "math",
               let glyph = formula(content,display:display,size:size,width:width,maxHeight:max(16,maxHeight-8)) {
                if display && source.length > 0 && !source.string.hasSuffix("\n") {
                    source.append(NSAttributedString(string:"\n",attributes:values))
                }
                source.append(attachment(glyph,attributes:values,display:display))
                if display { source.append(NSAttributedString(string:"\n",attributes:values)) }
                afterDisplay = display
            } else {
                var fallback = run["kind"] as? String == "math" ? (run["source"] as? String ?? content) : content
                if afterDisplay {
                    while fallback.hasPrefix("\n") { fallback.removeFirst() }
                }
                afterDisplay = false
                source.append(NSAttributedString(string:fallback,attributes:values))
            }
        }
        if source.length == 0 { return }
        let typesetter = CTTypesetterCreateWithAttributedString(source)
        var offset = 0
        while offset < source.length && lines.count < maxLines {
            let length = max(1,CTTypesetterSuggestLineBreak(typesetter,offset,width))
            let line = CTTypesetterCreateLine(typesetter,CFRange(location:offset,length:min(length,source.length-offset)))
            var ascent: CGFloat = 0, descent: CGFloat = 0
            CTLineGetTypographicBounds(line,&ascent,&descent,nil)
            let hasMath = (CTLineGetGlyphRuns(line) as! [CTRun]).contains {
                (CTRunGetAttributes($0) as NSDictionary)[mathKey] != nil
            }
            let rowHeight = max(leading,ascent+descent+(hasMath ? 8 : 0))
            if height + rowHeight > maxHeight + 0.01 { break }
            let center = (CTLineGetGlyphRuns(line) as! [CTRun]).contains {
                (CTRunGetAttributes($0) as NSDictionary)[displayKey] as? Bool == true
            }
            lines.append(Line(text:line,ascent:ascent,descent:descent,height:rowHeight,center:center))
            offset += length
        }
        if offset < source.length && !lines.isEmpty {
            // Ellipsize the last complete row instead of drawing a clipped formula.
            let last = lines.removeLast()
            let original = CTLineGetStringRange(last.text)
            let end = min(source.length,original.location+original.length)
            let tail = NSMutableAttributedString(attributedString:source.attributedSubstring(from:NSRange(location:original.location,length:end-original.location)))
            while tail.string.hasSuffix("\n") { tail.deleteCharacters(in:NSRange(location:tail.length-1,length:1)) }
            tail.append(NSAttributedString(string:" …",attributes:values))
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string:"…",attributes:values))
            let full = CTLineCreateWithAttributedString(tail)
            let clipped = CTLineCreateTruncatedLine(full,width,.end,ellipsis) ?? last.text
            lines.append(Line(text:clipped,ascent:last.ascent,descent:last.descent,height:last.height,center:last.center))
        }
    }

    func draw(x: Double, y: Double, width: Double) {
        var top = y
        for line in lines {
            let baseline = top + (line.height-line.ascent-line.descent)/2 + line.ascent
            let measured = CTLineGetTypographicBounds(line.text,nil,nil,nil)
            let left = x + (line.center ? max(0,(width-measured)/2) : 0)
            ctx.saveGState();ctx.translateBy(x:left,y:baseline);ctx.scaleBy(x:1,y:-1)
            ctx.textMatrix = .identity;ctx.textPosition = .zero;CTLineDraw(line.text,ctx);ctx.restoreGState()
            for run in CTLineGetGlyphRuns(line.text) as! [CTRun] {
                let values = CTRunGetAttributes(run) as NSDictionary
                guard let glyph = values[mathKey] as? FormulaGlyph else { continue }
                var position = CGPoint.zero
                CTRunGetPositions(run,CFRange(location:0,length:1),&position)
                glyph.image.draw(in:NSRect(x:left+position.x,y:baseline-glyph.ascent,width:glyph.width,height:glyph.ascent+glyph.descent),
                                 from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            }
            top += line.height
        }
    }
}
