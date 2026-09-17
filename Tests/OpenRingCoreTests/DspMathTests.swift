import Testing
import Foundation
@testable import OpenRingCore

@Suite("DSP Math & Physiological Algorithm Tests")
struct DspMathTests {
    
    @Test("rMSSD computation on synthetic IBI series")
    func testRmssdComputation() {
        // Inter-beat intervals (in ms) simulating steady resting heart rate around 60 bpm (1000ms) with minor HRV
        let ibiSeries: [Double] = [
            1000.0, 1020.0, 990.0, 1015.0, 980.0, 1030.0, 995.0, 1010.0
        ]
        
        let rmssd = SignalProcessor.computeRmssd(ibiSeries: ibiSeries)
        #expect(rmssd != nil)
        if let val = rmssd {
            #expect(val > 20.0 && val < 50.0)
        }
    }
    
    @Test("Artifact filtering in rMSSD computation")
    func testRmssdArtifactRejection() {
        // Series with an extreme motion jump (e.g. 2500ms and 150ms impossible intervals)
        let dirtySeries: [Double] = [
            1000.0, 1020.0, 150.0, 2500.0, 1010.0, 990.0
        ]
        
        let rmssd = SignalProcessor.computeRmssd(ibiSeries: dirtySeries)
        #expect(rmssd != nil)
    }
    
    @Test("Exponential Moving Average 14-day update")
    func testEmaBaselineUpdate() {
        // Initial baseline equals first day
        let day1 = SignalProcessor.updateExponentialMovingAverage(currentBaseline: nil, newDailyValue: 50.0)
        #expect(day1 == 50.0)
        
        // Day 2 update with alpha = 2 / 15 = 0.13333...
        let day2 = SignalProcessor.updateExponentialMovingAverage(currentBaseline: day1, newDailyValue: 60.0)
        #expect(day2 > 50.0 && day2 < 52.0)
    }
    
    @Test("Readiness score bounds and penalty calculation")
    func testReadinessScoring() {
        // Optimal conditions: no RHR elevation, no HRV suppression, normal temp, 100% sleep efficiency
        let optimalScore = SignalProcessor.computeReadinessScore(
            nightlyRhr: 50.0,
            baselineRhr: 52.0,
            nightlyHrv: 65.0,
            baselineHrv: 60.0,
            temperatureDeviationCelsius: 0.0,
            sleepEfficiencyPercent: 100.0
        )
        #expect(optimalScore == 100)
        
        // Severe strain conditions: +8 bpm RHR, -40% HRV, +0.65 C temp, 70% sleep efficiency
        let strainedScore = SignalProcessor.computeReadinessScore(
            nightlyRhr: 60.0,
            baselineRhr: 52.0,
            nightlyHrv: 36.0,
            baselineHrv: 60.0,
            temperatureDeviationCelsius: 0.65,
            sleepEfficiencyPercent: 70.0
        )
        #expect(strainedScore < 75)
        #expect(strainedScore >= 0)
    }
}

