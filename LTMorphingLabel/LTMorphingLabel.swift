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
    @IBInspectable open var morphingDuration: Float = 0.6
    @IBInspectable open var morphingCharacterDelay: Float = 0.026
    @IBInspectable open var morphingEnabled: Bool = true
    
    @IBOutlet open weak var delegate: LTMorphingLabelDelegate?
    open var morphingEffect: LTMorphingEffect = .scale
    
    var startClosures = [String: LTMorphingStartClosure]()
    var effectClosures = [String: LTMorphingEffectClosure]()
    var drawingClosures = [String: LTMorphingDrawingClosure]()
    var progressClosures = [String: LTMorphingManipulateProgressClosure]()
    var skipFramesClosures = [String: LTMorphingSkipFramesClosure]()
    var diffResults: LTStringDiffResult?
    var previousText = ""
    var previousAttributedText: NSAttributedString?
    
    var currentFrame = 0
    var totalFrames = 0
    var totalDelayFrames = 0
    
    var totalWidth: Float = 0.0
    var previousRects = [CGRect]()
    var newRects = [CGRect]()
    var charHeight: CGFloat = 0.0
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
            
            previousAttributedText = attributedText ?? NSAttributedString()
            diffResults = previousAttributedText!.string.diffWith(newAttributedText.string)
            super.attributedText = newValue
            
            morphingProgress = 0.0
            currentFrame = 0
            totalFrames = 0
            
            setNeedsLayout()
            
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
    }
    
    open override func setNeedsLayout() {
        super.setNeedsLayout()
        
        if let attributedText = self.attributedText {
            previousRects = rectsOfEachAttributedCharacter(previousAttributedText ?? NSAttributedString())
            newRects = rectsOfEachAttributedCharacter(attributedText)
        } else {
            previousRects = rectsOfEachCharacter(previousText, withFont: font)
            newRects = rectsOfEachCharacter(text ?? "", withFont: font)
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
    
    func displayFrameTick() {
        if displayLink.duration > 0.0 && totalFrames == 0 {
            let frameRate = Float(displayLink.duration) / Float(displayLink.frameInterval)
            totalFrames = Int(ceil(morphingDuration / frameRate))
            
            let totalDelay = Float((text!).characters.count) * morphingCharacterDelay
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
    
    fileprivate func rectsOfEachCharacter(_ textToDraw: String, withFont font: UIFont) -> [CGRect] {
        var charRects = [CGRect]()
        var leftOffset: CGFloat = 0.0
        
        charHeight = "Leg".size(attributes: [NSFontAttributeName: font]).height
        
        let topOffset = (bounds.size.height - charHeight) / 2.0
        
        for (_, char) in textToDraw.characters.enumerated() {
            let charSize = String(char).size(attributes: [NSFontAttributeName: font])
            charRects.append(
                CGRect(
                    origin: CGPoint(
                        x: leftOffset,
                        y: topOffset
                    ),
                    size: charSize
                )
            )
            leftOffset += charSize.width
        }
        
        totalWidth = Float(leftOffset)
        
        var stringLeftOffSet: CGFloat = 0.0
        
        switch textAlignment {
        case .center:
            stringLeftOffSet = CGFloat((Float(bounds.size.width) - totalWidth) / 2.0)
        case .right:
            stringLeftOffSet = CGFloat(Float(bounds.size.width) - totalWidth)
        default:
            ()
        }
        
        var offsetedCharRects = [CGRect]()
        
        for r in charRects {
            offsetedCharRects.append(r.offsetBy(dx: stringLeftOffSet, dy: 0.0))
        }
        
        return offsetedCharRects
    }
    
    fileprivate func rectsOfEachAttributedCharacter(_ attributedText: NSAttributedString) -> [CGRect] {
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
        
        let frameSetter = CTFramesetterCreateWithAttributedString(attributedText)
        var fitRange = CFRange()
        let fitSize = CTFramesetterSuggestFrameSizeWithConstraints(frameSetter, range, nil, bounds.size, &fitRange)
        
        let frameRect = CGRect(origin: .zero, size: fitSize)
        let framePath = CGPath(rect: frameRect, transform: nil)
        let frame = CTFramesetterCreateFrame(frameSetter, range, framePath, nil)
        
        let lines = CTFrameGetLines(frame) as! [CTLine]
        let lineCount = lines.count
        
        var lineOrigins = Array<CGPoint>(repeating: .zero, count: lineCount)
        var lineFrames = Array<CGRect>(repeating: .null, count: lineCount)
        
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &lineOrigins)
        
        for i in 0..<lineCount {
            let line = lines[i]
            
            let lineRange = CTLineGetStringRange(line)
            let lineStartIndex = lineRange.location
            let lineEndIndex = lineStartIndex + lineRange.length
            
            let lineOrigin = lineOrigins[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            
            let neighborLineY = i > 0 ? lineOrigins[i - 1].y : (lineCount - 1 > i ? lineOrigins[i + 1].y : 0.0)
            let lineHeight = ceil((i < lineCount - 1) ? abs(neighborLineY - lineOrigin.y) : ascent + descent + leading)
            
            lineFrames[i].origin = lineOrigin
            lineFrames[i].size = CGSize(width: CGFloat(lineWidth), height: lineHeight)
            
            for ic in lineStartIndex..<lineEndIndex {
                let startOffset = CTLineGetOffsetForStringIndex(line, ic, nil)
                characterFrames[ic].origin.x += startOffset
                characterFrames[ic].origin.y += lineOrigin.y
            }
        }
        
        return characterFrames
    }
    
    fileprivate func limboOfOriginalCharacter(
        _ char: Character,
        index: Int,
        progress: Float) -> LTCharacterLimbo {
        
        var currentRect = previousRects[index]
        let oriX = Float(currentRect.origin.x)
        var newX = Float(currentRect.origin.x)
        let diffResult = diffResults!.0[index]
        var currentFontSize: CGFloat = font.pointSize
        var currentAlpha: CGFloat = 1.0
        
        switch diffResult {
        // Move the character that exists in the new text to current position
        case .same:
            newX = Float(newRects[index].origin.x)
            currentRect.origin.x = CGFloat(
                LTEasing.easeOutQuint(progress, oriX, newX - oriX)
            )
        case .move(let offset):
            newX = Float(newRects[index + offset].origin.x)
            currentRect.origin.x = CGFloat(
                LTEasing.easeOutQuint(progress, oriX, newX - oriX)
            )
        case .moveAndAdd(let offset):
            newX = Float(newRects[index + offset].origin.x)
            currentRect.origin.x = CGFloat(
                LTEasing.easeOutQuint(progress, oriX, newX - oriX)
            )
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
                currentRect = previousRects[index].offsetBy(
                    dx: 0,
                    dy: CGFloat(font.pointSize - currentFontSize)
                )
            }
        }
        
        return LTCharacterLimbo(
            char: char,
            rect: currentRect,
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
            currentFontSize = CGFloat(
                LTEasing.easeOutQuint(progress, 0.0, Float(font.pointSize))
            )
            // For emojis
            currentFontSize = max(0.0001, currentFontSize)
            
            let yOffset = CGFloat(font.pointSize - currentFontSize)
            
            return LTCharacterLimbo(
                char: char,
                rect: currentRect.offsetBy(dx: 0, dy: yOffset),
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
            if i >= diffResults?.0.count {
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
            if diffResults?.skipDrawingResults[i] == true {
                continue
            }
            
            if let diffResult = diffResults?.0[i] {
                switch diffResult {
                case .moveAndAdd, .replace, .add, .delete:
                    let limboOfCharacter = limboOfNewCharacter(
                        character,
                        index: i,
                        progress: progress
                    )
                    limbo.append(limboOfCharacter)
                default:
                    ()
                }
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
        
        for charLimbo in limbo {
            let charRect = charLimbo.rect
            
            let willAvoidDefaultDrawing: Bool = {
                if let closure = drawingClosures[
                    "\(morphingEffect.description)\(LTMorphingPhases.draw)"
                    ] {
                    return closure($0)
                }
                return false
            }(charLimbo)
            
            if !willAvoidDefaultDrawing {
                let s = String(charLimbo.char)
                s.draw(in: charRect, withAttributes: [
                    NSFontAttributeName:
                        UIFont.init(name: font.fontName, size: charLimbo.size)!,
                    NSForegroundColorAttributeName:
                        textColor.withAlphaComponent(charLimbo.alpha)
                    ])
            }
        }
    }
    
}
