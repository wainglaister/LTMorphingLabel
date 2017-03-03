//
//  LTMorphingLabel.swift
//  https://github.com/lexrus/LTMorphingLabel
//
//  The MIT License (MIT)
//  Copyright (c) 2016 Lex Tang, http://lexrus.com
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files
//  (the “Software”), to deal in the Software without restriction,
//  including without limitation the rights to use, copy, modify, merge,
//  publish, distribute, sublicense, and/or sell copies of the Software,
//  and to permit persons to whom the Software is furnished to do so,
//  subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included
//  in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
//  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation
import UIKit
import QuartzCore
import CoreText

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l < r
    case (nil, _?):
        return true
    default:
        return false
    }
}

fileprivate func >= <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l >= r
    default:
        return !(lhs < rhs)
    }
}

enum LTMorphingPhases: Int {
    case start, appear, disappear, draw, progress, skipFrames
}

typealias LTMorphingStartClosure =
    (Void) -> Void

typealias LTMorphingEffectClosure =
    (Character, _ index: Int, _ progress: Float) -> LTCharacterLimbo

typealias LTMorphingDrawingClosure =
    (LTCharacterLimbo) -> Bool

typealias LTMorphingManipulateProgressClosure =
    (_ index: Int, _ progress: Float, _ isNewChar: Bool) -> Float

typealias LTMorphingSkipFramesClosure =
    (Void) -> Int

@objc public protocol LTMorphingLabelDelegate {
    @objc optional func morphingDidStart(_ label: LTMorphingLabel)
    @objc optional func morphingDidComplete(_ label: LTMorphingLabel)
    @objc optional func morphingOnProgress(_ label: LTMorphingLabel, progress: Float)
}

// MARK: - LTMorphingLabel
@IBDesignable open class LTMorphingLabel: UILabel {
    
    @IBInspectable open var morphingProgress: Float = 0.0
    @IBInspectable open var morphingDuration: Float = 5 //  0.6
    @IBInspectable open var morphingCharacterDelay: Float = 0.026
    @IBInspectable open var morphingEnabled: Bool = true
    
    @IBOutlet open weak var delegate: LTMorphingLabelDelegate?
    open var morphingEffect: LTMorphingEffect = .scale
    
    var startClosures = [String: LTMorphingStartClosure]()
    var effectClosures = [String: LTMorphingEffectClosure]()
    var drawingClosures = [String: LTMorphingDrawingClosure]()
    var progressClosures = [String: LTMorphingManipulateProgressClosure]()
    var skipFramesClosures = [String: LTMorphingSkipFramesClosure]()
    
    var previousText = ""
    var previousAttributedText: NSAttributedString?
    
    var currentFrame = 0
    var totalFrames = 0
    var totalDelayFrames = 0
    
    var diffResults: LTStringDiffResult = []
    var previousRects: [(glyph: CGGlyph, line: CGFloat, rect: CGRect)] = []
    var newRects: [(glyph: CGGlyph, line: CGFloat, rect: CGRect)] = []
    
    var skipFramesCount: Int = 0
    
    #if TARGET_INTERFACE_BUILDER
    let presentingInIB = true
    #else
    let presentingInIB = false
    #endif
    
    override open var font: UIFont! {
        get {
            return super.font
        }
        set {
            guard font != newValue else { return }
            guard self.text != nil else {
                super.font = font
                return
            }
            
            let attributedText = NSAttributedString(string: self.text,
                                                    attributes: [
                                                        NSFontAttributeName : font,
                                                        NSForegroundColorAttributeName : textColor
                ])
            
            self.attributedText = attributedText
        }
    }
    
    override open var textColor: UIColor! {
        get {
            return super.textColor
        }
        set {
            guard textColor != newValue else { return }
            guard self.text != nil else {
                super.textColor = textColor
                return
            }
            
            let attributedText = NSAttributedString(string: self.text,
                                                    attributes: [
                                                        NSFontAttributeName : font,
                                                        NSForegroundColorAttributeName : textColor
                ])
            
            self.attributedText = attributedText
        }
    }
    
    override open var text: String! {
        get {
            return super.text
        }
        set {
            print("set text '\(text ?? "")' -> '\(newValue!)'")
            
            guard text != newValue else { return }
            
            let attributedText = NSAttributedString(string: newValue,
                                                    attributes: [
                                                        NSFontAttributeName : font,
                                                        NSForegroundColorAttributeName : textColor
                ])
            
            self.attributedText = attributedText
        }
    }
    
    override open var attributedText: NSAttributedString? {
        get {
            return super.attributedText
        }
        set {
            let newAttributedText = newValue ?? NSAttributedString()
            guard attributedText != newValue else { return }
            
            print("set ATTR text '\((attributedText ?? NSAttributedString()).string)' -> '\(newAttributedText.string)'")
            
            self.handleTextChange(from: attributedText, to: newAttributedText)
            
            super.attributedText = newValue
            
            setNeedsLayout()
        }
    }
    
    fileprivate func handleTextChange(from: NSAttributedString?, to newAttributedText: NSAttributedString) {
        
        print("handleTextChange")
        
        previousAttributedText = from ?? NSAttributedString()
        
        let text = newAttributedText.string
        previousText = previousAttributedText!.string
        
        diffResults = previousAttributedText!.diffWith(newAttributedText, inSize: bounds.size)
        
        morphingProgress = 0.0
        currentFrame = 0
        totalFrames = 0
        
        if !morphingEnabled {
            return
        }
        
        if presentingInIB {
            morphingDuration = 0.01
            morphingProgress = 0.5
        } else if previousText != text {
            displayLink.isPaused = false
            let closureKey = "\(morphingEffect.description)\(LTMorphingPhases.start)"
            if let closure = startClosures[closureKey] {
                return closure()
            }
            
            delegate?.morphingDidStart?(self)
        }
    }
    
    open override func setNeedsLayout() {
        super.setNeedsLayout()
        
        print("needs layout")
        
        if let attributedText = self.attributedText {
            let previous = previousAttributedText ?? NSAttributedString()
            
            print("needs layout -->>>> '\(previous.string)' -> '\(attributedText.string)'")
            
            previousRects = rectsOfEachAttributedCharacter(previous)
            newRects = rectsOfEachAttributedCharacter(attributedText)
        }
    }
    
    override open var bounds: CGRect {
        get {
            return super.bounds
        }
        set {
            super.bounds = newValue
            setNeedsLayout()
        }
    }
    
    override open var frame: CGRect {
        get {
            return super.frame
        }
        set {
            super.frame = newValue
            setNeedsLayout()
        }
    }
    
    fileprivate lazy var displayLink: CADisplayLink = {
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(LTMorphingLabel.displayFrameTick))
        displayLink.add(
            to: RunLoop.current,
            forMode: RunLoopMode.commonModes)
        return displayLink
    }()
    
    lazy var emitterView: LTEmitterView = {
        let emitterView = LTEmitterView(frame: self.bounds)
        self.addSubview(emitterView)
        return emitterView
    }()
}

// MARK: - Animation extension
extension LTMorphingLabel {
    
    fileprivate func rectsOfEachAttributedCharacter(_ attributedText: NSAttributedString) -> [(CGGlyph, CGFloat, CGRect)] {
        let string = attributedText.string as CFString
        let length = attributedText.length
        
        guard length > 0 else { return [] }
        
        let range = CFRangeMake(0, length)
        
        var chars = Array<UniChar>(repeating: 0, count: length)
        CFStringGetCharacters(string, range, &chars)
        
        var glyphs = Array<CGGlyph>(repeating: 0, count: length)
        CTFontGetGlyphsForCharacters(font, &chars, &glyphs, length)
        
        var characterFrames = Array<CGRect>(repeating: .null, count: length)
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyphs, &characterFrames, length)
        
        let (_, frame, lines) = attributedText.framesetterInfo(inSize: bounds.size)
        let lineCount = lines.count
        
        var lineOrigins = Array<CGPoint>(repeating: .zero, count: lineCount)
        
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &lineOrigins)
        
        var rects: [(CGGlyph, CGFloat, CGRect)] = []
        let totalLineOffset = lineOrigins.first!.y
        
        var ic = 0
        
        for i in 0..<lineCount {
            let line = lines[i]
            
            let lineRange = CTLineGetStringRange(line)
            let lineStartIndex = lineRange.location
            let lineEndIndex = lineStartIndex + lineRange.length
            
            let lineOrigin = lineOrigins[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            
            let neighborLineY = i > 0 ? lineOrigins[i - 1].y : (lineCount - 1 > i ? lineOrigins[i + 1].y : 0.0)
            let lineHeight = ceil((i < lineCount - 1) ? abs(neighborLineY - lineOrigin.y) : ascent + descent + leading)
            let lineOffset = totalLineOffset - lineOrigin.y + lineHeight
            
            for stringIndex in lineStartIndex..<lineEndIndex {
                let startOffset = CTLineGetOffsetForStringIndex(line, stringIndex, nil)
                characterFrames[ic].origin.x += startOffset
                
                rects.append((glyphs[ic], lineOffset, characterFrames[ic]))
                
                ic += 1
            }
        }
        
        return rects
    }
    
    fileprivate func limboOfOriginalCharacter(
        _ char: Character,
        index: Int,
        progress: Float) -> LTCharacterLimbo {
        
        var currentRect = previousRects[index]
        let oriX = Float(currentRect.rect.origin.x)
        var newX: Float!
        let oriY = Float(currentRect.line)
        var newY: Float!
        let diffResult = diffResults[index].0
        var currentFontSize: CGFloat = font.pointSize
        var currentAlpha: CGFloat = 1.0
        
        switch diffResult {
        // Move the character that exists in the new text to current position
        case .same:
            newX = Float(newRects[index].rect.origin.x)
            currentRect.rect.origin.x = CGFloat(
                LTEasing.easeOutQuint(progress, oriX, newX - oriX)
            )
            newY = Float(newRects[index].line)
            if fabs(newY - oriY) > 0.01 {
                currentRect.line = CGFloat(
                    LTEasing.easeOutQuint(progress, oriY, newY - oriY)
                )
            }
        case .move(let offset):
            newX = Float(newRects[index + offset].rect.origin.x)
            currentRect.rect.origin.x = CGFloat(
                LTEasing.easeOutQuint(progress, oriX, newX - oriX)
            )
            newY = Float(newRects[index + offset].line)
            if fabs(newY - oriY) > 0.01 {
                currentRect.line = CGFloat(
                    LTEasing.easeOutQuint(progress, oriY, newY - oriY)
                )
            }
        case .moveAndAdd(let offset):
            newX = Float(newRects[index + offset].rect.origin.x)
            currentRect.rect.origin.x = CGFloat(
                LTEasing.easeOutQuint(progress, oriX, newX - oriX)
            )
            newY = Float(newRects[index + offset].line)
            if fabs(newY - oriY) > 0.01 {
                currentRect.line = CGFloat(
                    LTEasing.easeOutQuint(progress, oriY, newY - oriY)
                )
            }
        default:
            // Otherwise, remove it
            
            // Override morphing effect with closure in extenstions
            if let closure = effectClosures[
                "\(morphingEffect.description)\(LTMorphingPhases.disappear)"
                ] {
                return closure(char, index, progress)
            } else {
                // And scale it by default
                let fontEase = CGFloat(
                    LTEasing.easeOutQuint(
                        progress, 0, Float(font.pointSize)
                    )
                )
                // For emojis
                currentFontSize = max(0.0001, font.pointSize - fontEase)
                currentAlpha = CGFloat(1.0 - progress)
                currentRect.rect = currentRect.rect.offsetBy(
                    dx: 0,
                    dy: CGFloat(font.pointSize - currentFontSize)
                )
            }
        }
        
        return LTCharacterLimbo(
            incoming: false,
            char: char,
            glyph: currentRect.glyph,
            lineOffset: currentRect.line,
            rect: currentRect.rect,
            alpha: currentAlpha,
            size: currentFontSize,
            drawingProgress: 0.0
        )
    }
    
    fileprivate func limboOfNewCharacter(
        _ char: Character,
        index: Int,
        progress: Float) -> LTCharacterLimbo {
        
        let currentRect = newRects[index]
        var currentFontSize = CGFloat(
            LTEasing.easeOutQuint(progress, 0, Float(font.pointSize))
        )
        
        if let closure = effectClosures[
            "\(morphingEffect.description)\(LTMorphingPhases.appear)"
            ] {
            return closure(char, index, progress)
        } else {
            // For emojis
            currentFontSize = max(0.0001, currentFontSize)
            
            let yOffset = CGFloat(font.pointSize - currentFontSize)
            
            return LTCharacterLimbo(
                incoming: true,
                char: char,
                glyph: currentRect.glyph,
                lineOffset: currentRect.line,
                rect: currentRect.rect.offsetBy(dx: 0, dy: yOffset),
                alpha: CGFloat(morphingProgress),
                size: currentFontSize,
                drawingProgress: 0.0
            )
        }
    }
    
    fileprivate func limboOfCharacters() -> [LTCharacterLimbo] {
        var limbo = [LTCharacterLimbo]()
        
        // Iterate original characters
        for (i, character) in previousText.characters.enumerated() {
            var progress: Float = 0.0
            
            if let closure = progressClosures[
                "\(morphingEffect.description)\(LTMorphingPhases.progress)"
                ] {
                progress = closure(i, morphingProgress, false)
            } else {
                progress = min(1.0, max(0.0, morphingProgress + morphingCharacterDelay * Float(i)))
            }
            
            let limboOfCharacter = limboOfOriginalCharacter(character, index: i, progress: progress)
            limbo.append(limboOfCharacter)
        }
        
        // Add new characters
        for (i, character) in (text!).characters.enumerated() {
            if i >= diffResults.count {
                break
            }
            
            var progress: Float = 0.0
            
            if let closure = progressClosures[
                "\(morphingEffect.description)\(LTMorphingPhases.progress)"
                ] {
                progress = closure(i, morphingProgress, true)
            } else {
                progress = min(1.0, max(0.0, morphingProgress - morphingCharacterDelay * Float(i)))
            }
            
            // Don't draw character that already exists
            if diffResults[i].skipDrawingResults {
                continue
            }
            
            let diffResult = diffResults[i].0
            
            switch diffResult {
            case .moveAndAdd, .replace, .add, .delete:
                let limboOfCharacter = limboOfNewCharacter(
                    character,
                    index: i,
                    progress: progress
                )
                limbo.append(limboOfCharacter)
            default:
                break
            }
        }
        
        return limbo
    }
    
}

// MARK: - Drawing extension
extension LTMorphingLabel {
    
    override open func didMoveToSuperview() {
        if let s = text {
            text = s
        }
        
        // Load all morphing effects
        for effectName: String in LTMorphingEffect.allValues {
            let effectFunc = Selector("\(effectName)Load")
            if responds(to: effectFunc) {
                perform(effectFunc)
            }
        }
    }
    
    open override func awakeFromNib() {
        super.awakeFromNib()
        
        if let attributedText = self.attributedText {
            self.handleTextChange(from: nil, to: attributedText)
            setNeedsLayout()
        } else {
            let attributedText = NSAttributedString(string: self.text,
                                                    attributes: [
                                                        NSFontAttributeName : font,
                                                        NSForegroundColorAttributeName : textColor
                ])
            
            self.attributedText = attributedText
        }
    }
    
    func displayFrameTick() {
        if displayLink.duration > 0.0 && totalFrames == 0 {
            let count = max(1, Float(text!.characters.count))
            
            let frameRate = Float(displayLink.duration) / Float(displayLink.frameInterval)
            totalFrames = Int(ceil(morphingDuration / (frameRate * count)))
            
            let totalDelay = count * morphingCharacterDelay
            totalDelayFrames = Int(ceil(totalDelay / frameRate))
        }
        
        currentFrame += 1
        
        if previousText != text && currentFrame < totalFrames + totalDelayFrames + 5 {
            morphingProgress += 1.0 / Float(totalFrames)
            
            let closureKey = "\(morphingEffect.description)\(LTMorphingPhases.skipFrames)"
            if let closure = skipFramesClosures[closureKey] {
                skipFramesCount += 1
                if skipFramesCount > closure() {
                    skipFramesCount = 0
                    setNeedsDisplay()
                }
            } else {
                setNeedsDisplay()
            }
            
            if let onProgress = delegate?.morphingOnProgress {
                onProgress(self, morphingProgress)
            }
        } else {
            displayLink.isPaused = true
            
            delegate?.morphingDidComplete?(self)
        }
    }
    
    override open func drawText(in rect: CGRect) {
        guard morphingEnabled else {
            super.drawText(in: rect)
            return
        }
        
        let limbo = limboOfCharacters()
        
        guard !limbo.isEmpty else {
            super.drawText(in: rect)
            return
        }
        
        let context = UIGraphicsGetCurrentContext()!
        //let height = bounds.size.height
        
        context.textMatrix = .identity
        //context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        
        context.setStrokeColor(UIColor.blue.cgColor)
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: 100, height: 100)).stroke()
        context.setStrokeColor(UIColor.brown.cgColor)
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: 200, height: 100)).stroke()
        
        
        let cgFont = CTFontCopyGraphicsFont(font, nil)
        context.setFont(cgFont)
        context.setFontSize(CTFontGetSize(font))
        
        
        for charLimbo in limbo {
            context.saveGState()
            
            let charRect = charLimbo.rect
            
            //            let willAvoidDefaultDrawing: Bool = {
            //                if let closure = drawingClosures[
            //                    "\(morphingEffect.description)\(LTMorphingPhases.draw)"
            //                    ] {
            //                    return closure($0)
            //                }
            //                return false
            //            }(charLimbo)
            //
            //            if !willAvoidDefaultDrawing {
            //            let s = String(charLimbo.char)
            //s.draw(in: charRect, withAttributes: [
            //            s.draw(in: CGRect(origin: charRect.origin, size: CGSize(width: 50, height: 50)), withAttributes: [
            //                NSFontAttributeName:
            //                    UIFont.init(name: font.fontName, size: charLimbo.size)!,
            //                NSForegroundColorAttributeName:
            //                    textColor.withAlphaComponent(charLimbo.alpha)
            //                ])
            
            context.setFontSize(charLimbo.size)
            
            context.translateBy(x: 0, y: -charLimbo.lineOffset)
            context.translateBy(x: 0, y: -charRect.origin.y)
            
            
            
            if charLimbo.incoming {
                context.setStrokeColor(UIColor.green.withAlphaComponent(0.3).cgColor)
            } else {
                context.setStrokeColor(UIColor.red.withAlphaComponent(0.2).cgColor)
            }
            
            UIBezierPath(rect: charRect).stroke()
            
            context.setFillColor(textColor.withAlphaComponent(charLimbo.alpha).cgColor)
            context.showGlyphs([charLimbo.glyph], at: [charRect.origin])
            
            context.restoreGState()
        }
        //        }
    }
    
}
