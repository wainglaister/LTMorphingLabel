//
//  LTStringDiffResult.swift
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
import CoreText

public typealias LTStringDiffResult = [(LTCharacterDiffResult, skipDrawingResults: Bool)]

private func NSMakeRangeFromCF(_ cfr: CFRange) -> NSRange { return NSMakeRange( cfr.location == kCFNotFound ? NSNotFound : cfr.location, cfr.length ) }

public extension NSAttributedString {
    
    func framesetterInfo(inSize size: CGSize) -> (CTFramesetter, CTFrame, [CTLine]) {
        let range = CFRangeMake(0, length)
        
        let frameSetter = CTFramesetterCreateWithAttributedString(self)
        var fitRange = CFRange()
        let fitSize = CTFramesetterSuggestFrameSizeWithConstraints(frameSetter, range, nil, size, &fitRange)
        
        let frameRect = CGRect(origin: .zero, size: fitSize)
        let framePath = CGPath(rect: frameRect, transform: nil)
        let frame = CTFramesetterCreateFrame(frameSetter, range, framePath, nil)
        
        let lines = CTFrameGetLines(frame) as! [CTLine]
        
        return (frameSetter, frame, lines)
    }
    
    private func lineChars(_ line: CTLine) -> [Character] {
        let lineRange = CTLineGetStringRange(line)
        let underlyingString = self.attributedSubstring(from: NSMakeRangeFromCF(lineRange)).string
        return Array(underlyingString.characters)
    }
    
    public func diffWith(_ anotherString: NSAttributedString, inSize size: CGSize) -> LTStringDiffResult {
        let lhsLength = self.length
        let rhsLength = anotherString.length
        let maxLength = max(lhsLength, rhsLength)
        
        guard rhsLength > 0 else {
            let diffResults: LTStringDiffResult =
                Array(repeating: (.delete, false), count: lhsLength)
            return diffResults
        }
        
        var diffResults: LTStringDiffResult =
            Array(repeating: (.add, false), count: maxLength)
        
        guard lhsLength > 0 else {
            return diffResults
        }
        
        let lhsChars = Array(self.string.characters)
        let rhsChars = anotherString.string.characters
        
        var skipIndexes = [Int]()
        
        for charcterIndex in 0..<maxLength {
            // If new string is longer than the original one
            if charcterIndex > (lhsLength - 1) {
                continue
            }
            
            let leftChar = lhsChars[charcterIndex]
            
            // Search left character in the new string
            var foundCharacterInRhs = false
            
            for (j, newChar) in rhsChars.enumerated() {
                if skipIndexes.contains(j) || leftChar != newChar {
                    continue
                }
                
                skipIndexes.append(j)
                foundCharacterInRhs = true
                
                if charcterIndex == j {
                    // Character not changed
                    diffResults[charcterIndex].0 = .same
                } else {
                    // foundCharacterInRhs and move
                    let offset = j - charcterIndex
                    
                    if charcterIndex <= (rhsLength - 1) {
                        // Move to a new index and add a new character to new original place
                        diffResults[charcterIndex].0 = .moveAndAdd(offset: offset)
                    } else {
                        diffResults[charcterIndex].0 = .move(offset: offset)
                    }
                    
                    diffResults[j].skipDrawingResults = true
                }
                
                break
            }
            
            if !foundCharacterInRhs {
                if charcterIndex < (rhsLength - 1) {
                    diffResults[charcterIndex].0 = .replace
                } else {
                    diffResults[charcterIndex].0 = .delete
                }
            }
        }
        
        return diffResults
    }
}
