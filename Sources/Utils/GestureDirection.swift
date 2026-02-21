import Foundation

/// 定义手势滑动方向的枚举
enum GestureDirection {
    case left
    case right
    case up
    case down
    case none

    /// 根据偏移量计算手势方向
    /// - Parameters:
    ///   - translation: 滑动的偏移量
    ///   - threshold: 触发滑动的最小阈值
    /// - Returns: 手势方向
    static func from(translation: CGSize, threshold: CGFloat = 80) -> GestureDirection {
        let absWidth = abs(translation.width)
        let absHeight = abs(translation.height)

        // 如果两个方向都小于阈值，返回none
        if absWidth < threshold && absHeight < threshold {
            return .none
        }

        // 优先考虑绝对值更大的方向
        if absWidth > absHeight {
            return translation.width > 0 ? .right : .left
        } else {
            return translation.height < 0 ? .up : .down
        }
    }
}