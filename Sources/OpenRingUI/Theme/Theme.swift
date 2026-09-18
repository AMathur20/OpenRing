import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Semantic styling tokens, physiological recovery color hierarchy, and adaptive surfaces (DEC-018).
public enum Theme {
    
    // MARK: - Dynamic Surface Colors (System-Adaptive Light/Dark Mode)
    
    public static var background: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color.black
        #endif
    }
    
    public static var secondaryBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(white: 0.12)
        #endif
    }
    
    public static var tertiaryBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .tertiarySystemBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .underPageBackgroundColor)
        #else
        return Color(white: 0.18)
        #endif
    }
    
    public static var cardBorder: Color {
        #if canImport(UIKit)
        return Color(uiColor: .separator).opacity(0.3)
        #elseif canImport(AppKit)
        return Color(nsColor: .separatorColor).opacity(0.3)
        #else
        return Color.white.opacity(0.1)
        #endif
    }
    
    // MARK: - Physiological Recovery Palette
    
    /// Optimal autonomic recovery and sleep restoration (Score >= 85)
    public static let optimal = Color(red: 16/255, green: 185/255, blue: 129/255) // Emerald #10B981
    
    /// Nominal physiological readiness and sleep quality (Score 70-84)
    public static let nominal = Color(red: 14/255, green: 165/255, blue: 233/255) // Sky Blue #0EA5E9
    
    /// Moderate physiological strain or mild sleep fragmentation (Score 55-69)
    public static let strain = Color(red: 245/255, green: 158/255, blue: 11/255) // Amber #F59E0B
    
    /// Marked autonomic strain or acute recovery deficit (Score < 55)
    public static let critical = Color(red: 239/255, green: 68/255, blue: 68/255) // Coral #EF4444
    
    // MARK: - Sleep Architecture Stage Palette
    
    /// Deep restorative slow-wave sleep (N3)
    public static let deepSleep = Color(red: 99/255, green: 102/255, blue: 241/255) // Indigo #6366F1
    
    /// REM cognitive and neurological restoration
    public static let remSleep = Color(red: 168/255, green: 85/255, blue: 247/255) // Purple #A855F7
    
    /// Light transitional sleep (N1/N2)
    public static let lightSleep = Color(red: 20/255, green: 184/255, blue: 166/255) // Teal #14B8A6
    
    /// Nocturnal awakenings and latency
    public static let awake = Color(red: 156/255, green: 163/255, blue: 175/255) // Gray #9CA3AF
    
    // MARK: - Score Mapping Helpers
    
    public static func scoreColor(for score: Int) -> Color {
        switch score {
        case 85...100: return optimal
        case 70...84: return nominal
        case 55...69: return strain
        default: return critical
        }
    }
    
    public static func scoreTierTitle(for score: Int) -> String {
        switch score {
        case 85...100: return "Optimal Recovery"
        case 70...84: return "Good Recovery"
        case 55...69: return "Moderate Strain"
        default: return "Critical Recovery"
        }
    }
    
    public static func sleepTierTitle(for score: Int) -> String {
        switch score {
        case 85...100: return "Optimal Sleep"
        case 70...84: return "Good Rest"
        case 55...69: return "Fair Rest"
        default: return "Fragmented Sleep"
        }
    }
}

