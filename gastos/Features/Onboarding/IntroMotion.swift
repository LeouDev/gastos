import Foundation

/// The first-open welcome animation, as pure functions of elapsed time so it can be tested.
/// Port of `ballPhysics` / `rise` from the design handoff (design_handoff_welcome_roll_in).
enum IntroMotion {
    static let duration = 5.8
    /// Continue becomes tappable once it has fully risen in.
    static let interactiveAt = reveal + 0.55 + 0.6
    static let landing = 0.6

    static let size = 220.0
    private static let radius = size / 2
    private static let reveal = 3.0
    private static let startX = -430.0
    private static let fallHeight = 760.0

    struct Ball: Equatable {
        var x = 0.0, y = 0.0, rotation = 0.0, scaleX = 1.0, scaleY = 1.0
        /// 1 on the floor, 0 when 160pt or more above it. Drives the sphere's own shadows.
        var grounded: Double { clamp(1 + y / 160) }
    }

    struct Rise: Equatable {
        var opacity = 1.0, y = 0.0, scale = 1.0
    }

    static func ball(at t: Double, bounce: Double = 1.1) -> Ball {
        let hops: [(duration: Double, height: Double, squash: Double)] = [
            (0.42, 96 * bounce, 0.16),
            (0.26, 30 * bounce, 0.08),
            (0.16, 9 * bounce, 0.04),
        ]
        var ball = Ball()

        // Vertical: gravity fall, then three shrinking hops.
        var impacts: [(t: Double, k: Double)] = [(landing, 0.18)]
        if t < landing {
            let u = clamp(t / landing)
            ball.y = -fallHeight * (1 - u * u)
        } else {
            var start = landing
            for hop in hops {
                if t < start + hop.duration {
                    let u = (t - start) / hop.duration
                    ball.y = -4 * hop.height * u * (1 - u)
                    break
                }
                start += hop.duration
                impacts.append((start, hop.squash))
            }
        }

        // Squash at each impact, stretch just before the first landing.
        let squash = impacts.reduce(0.0) { sum, impact in
            let dt = t - impact.t
            return dt >= 0 && dt < 0.16 ? sum + impact.k * sin(.pi * dt / 0.16) : sum
        }
        let stretch = t < landing ? 0.07 * clamp(1 - (landing - t) / 0.18) : 0
        ball.scaleX = 1 + squash - stretch / 2
        ball.scaleY = 1 - squash + stretch

        // Horizontal: one decelerating roll, small overshoot, rock back to rest.
        let rollEnd = reveal - 0.35
        if t < rollEnd - 0.5 {
            ball.x = startX + (18 - startX) * easeOutCubic(clamp(t / (rollEnd - 0.5)))
        } else {
            ball.x = 18 * (1 - easeInOutSine(clamp((t - (rollEnd - 0.5)) / 0.5)))
        }
        // Rolling without slipping, so the logo is upright exactly when x is 0.
        ball.rotation = ball.x / radius * 180 / .pi
        return ball
    }

    static func wordmark(at t: Double) -> Rise {
        let p = easeOutBack(clamp((t - reveal) / 0.6))
        return Rise(opacity: clamp(p * 2), y: (1 - p) * 18, scale: 0.86 + 0.14 * p)
    }

    static func tagline(at t: Double) -> Rise { rise(t, start: reveal + 0.28, distance: 14, duration: 0.55) }
    static func button(at t: Double) -> Rise { rise(t, start: reveal + 0.55, distance: 36, duration: 0.6) }

    private static func rise(_ t: Double, start: Double, distance: Double, duration: Double) -> Rise {
        let p = easeOutCubic(clamp((t - start) / duration))
        return Rise(opacity: clamp(p * 1.4), y: (1 - p) * distance)
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
    private static func easeOutCubic(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
    private static func easeInOutSine(_ p: Double) -> Double { -(cos(.pi * p) - 1) / 2 }
    private static func easeOutBack(_ p: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)
    }
}
