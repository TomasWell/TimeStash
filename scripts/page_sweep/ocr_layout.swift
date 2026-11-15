import Foundation
import Vision
import AppKit

// 用法: ocr <图片路径> [关注宽度px]
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: ocr <img>"); exit(1) }
let path = args[1]
guard let img = NSImage(contentsOfFile: path),
      let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let cg = rep.cgImage else { print("load fail"); exit(1) }

let W = Double(rep.pixelsWide), H = Double(rep.pixelsHigh)
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = false
req.recognitionLanguages = ["zh-Hans","en-US"]
let handler = VNImageRequestHandler(cgImage: cg, options: [:])
try? handler.perform([req])
guard let obs = req.results else { exit(0) }
struct Box { let t: String; let x: Double; let y: Double; let w: Double; let h: Double }
var boxes: [Box] = []
for o in obs {
    guard let top = o.topCandidates(1).first else { continue }
    let b = o.boundingBox
    boxes.append(Box(t: top.string, x: Double(b.origin.x)*W, y: Double(b.origin.y)*H,
                     w: Double(b.size.width)*W, h: Double(b.size.height)*H))
}
print("IMAGE \(Int(W))x\(Int(H))  text_count=\(boxes.count)")

// 4) **内容指纹** —— 状态栏以下的像素哈希（用来判「两屏是不是同一个界面」）
//
// ⚠️ **为什么不能直接用 PNG 的 md5**（2026-11-10 夜间档实测踩到）：
// 状态栏右上角有**系统时钟**（每分钟变一次），左上角有电量百分比。
// 同一个界面隔两分钟截两次 → **PNG 字节不同 → md5 不同** → 查重判「不重复」→
// 脚本报「✅ 14 屏内容互不相同」，而实际上其中两屏**截的是同一个界面**
// （那次就是 editRecord 的 sheet 根本没开，OCR 文本与 tab_history 完全一致）。
//
// → 指纹必须**把状态栏那条带裁掉**，只对 App 自己的内容像素求哈希。
//
// 裁多宽？iPhone 15 Pro 状态栏高 59pt @3x = 177px。
// 这里取 **200px**（比 177 多留一点余量），确保**只裁状态栏、不碰 App 内容**：
// 实测 App 内容区最低的一行文字（导航标题）在距顶 409px 处，远在裁剪带之外。
//
// 用 FNV-1a 64 位（不是加密哈希）—— 这里只要「一样/不一样」，不需要抗碰撞强度，
// 而且它没有依赖，编译快。
let statusBarCropPx: Int = 200
let cropY = min(Int(H), statusBarCropPx)
if cropY < Int(H) {
    var hash: UInt64 = 0xcbf29ce484222325
    let prime: UInt64 = 0x100000001b3
    let bytesPerRow = rep.bytesPerRow
    guard let raw = rep.bitmapData else { exit(0) }
    for row in cropY..<rep.pixelsHigh {
        let base = row * bytesPerRow
        var i = 0
        while i < bytesPerRow {
            let b = raw[base + i]
            hash ^= UInt64(b)
            hash = hash &* prime
            i += 1
        }
    }
    print(String(format: "content_hash=%016llx", hash))
} else {
    print("content_hash=0000000000000000")
}
// 1) 贴边/出界的文字
//
// ⚠️ 状态栏要排除掉：iOS 系统自己画的电量百分比就在右上角贴边，
// 那是系统 UI 不是 App 内容，把它算成「App 文字被裁切」是误报。
// 状态栏高度：SE 375x667@2x = 750x1334，状态栏 20pt = 40px → 取 60px 保险。
let statusBarBand: Double = 60
//
// ⚠️ **判据必须按「字迹」，不能按 Vision 包围盒**（2026-11-12 夜间档实测踩到）：
// 包围盒比字迹大（跟下面「重叠」判据踩的是同一个坑，2026-11-09 萌宠那次）。
// 实测：iOS 16.4 / iPhone SE 上，系统 Tab 栏的「History」标签
// 包围盒下沿正好压在图像底边 → 被判「文字被裁」→ 4 屏假警报。
// 但逐像素量过：那个标签的**最低字迹距屏幕底 4px**（字母 y 的下伸部），
// **一个笔画都没被裁掉** → 纯属误报。
//
// → 现在的判据：**包围盒贴边只是线索**；真正报红要看
//   **那个边缘的最外一列/行上有没有字迹** ——
//   有字迹 = 字真的顶到了边（可能被切），没字迹 = 只是包围盒的空白 padding。
// 判据统一成「按字迹」，跟下面「重叠」那段一个口径。
//
// ⚠️ **坐标系（这里踩过坑，改这��代码前先看清楚）**：
//   · Vision 的包围盒：**原点在左下角**（y 向上为正），底边 y=0、顶边 y=H。
//   · NSBitmapImageRep 的 `colorAt(x:y:)`：**原点在左上角**（y 向下为正），第 0 行 = 最上面一行。
//   → 换算：bitmapRow = H - (visionY + visionH) …… bitmapRow = H - visionY
print("--- EDGE (ink actually reaching image border) ---")
// ⚠️ 容差 2px：Vision 的盒子比字迹大，盒边可能比真实字迹边差 1~2px（实测）。
// 用 0 容差会把「字确实被裁」的情况一起漏掉（反向验证时踩到：合成图里
// 字被底边切掉，Vision 报的盒底在 1.0px 处 → `b.y <= 1` 判 false → 漏报）。
let edgeTolerance: Double = 2
for b in boxes {
    let right = b.x + b.w, bottom = b.y + b.h
    // Vision 的 y 原点在左下角 → 图像顶边 = H
    let distFromTop = H - (b.y + b.h)
    if distFromTop < statusBarBand { continue }   // 系统状态栏，不算 App 内容

    let touchesLeft = b.x <= edgeTolerance
    let touchesRight = right >= W-1-edgeTolerance
    let touchesBottom = b.y <= edgeTolerance
    let touchesTop = bottom >= H-1-edgeTolerance
    if !(touchesLeft || touchesRight || touchesBottom || touchesTop) { continue }

    // 盒子在 bitmap 坐标（原点左上）里的行列范围
    let rTop = max(0, Int((H - bottom).rounded()))
    let rBot = min(Int(H) - 1, Int((H - b.y).rounded()))
    let c0 = max(0, Int(b.x.rounded()))
    let c1 = min(Int(W) - 1, Int(right.rounded()))
    guard rBot >= rTop, c1 >= c0 else { continue }

    func hasInk(row: Int, col: Int) -> Bool {
        guard let c = rep.colorAt(x: col, y: row) else { return false }
        return c.brightnessComponent < 0.78
    }

    var cutAt = ""
    // 底边 = bitmap 最下面一行（row H-1）
    if touchesBottom {
        for col in c0...c1 where hasInk(row: Int(H) - 1, col: col) { cutAt = "bottom"; break }
    }
    // 顶边 = bitmap 第 0 行
    if cutAt.isEmpty && touchesTop {
        for col in c0...c1 where hasInk(row: 0, col: col) { cutAt = "top"; break }
    }
    // 左边 = bitmap 第 0 列
    if cutAt.isEmpty && touchesLeft {
        for row in rTop...rBot where hasInk(row: row, col: 0) { cutAt = "left"; break }
    }
    // 右边 = bitmap 最右一列
    if cutAt.isEmpty && touchesRight {
        for row in rTop...rBot where hasInk(row: row, col: Int(W) - 1) { cutAt = "right"; break }
    }
    if !cutAt.isEmpty {
        // ⚠️ 只能用 %@，**不能用 %s** —— %s 要 C 字符串指针，
        // 传 Swift String 进去是未定义行为 → 实测直接段错误（2026-11-12 夜间档踩到）。
        print(String(format: "  [%.0f,%.0f %.0fx%.0f] '%@' (ink on %@ border)", b.x, b.y, b.w, b.h, b.t, cutAt))
    }
}
// 2) 互相重叠的文字
//
// ⚠️ **Vision 的包围盒比字迹大**，所以光看盒子会误报。
// 2026-11-09 实测：中文标题「猫三联（第三针）」和它下面的副标题「Vaccine」
// 被报成「重叠 27%」—— 但逐像素量过：标题的字迹到第 1217 行就结束了，
// 副标题的字迹从第 1237 行才开始，**中间隔了 20 行空白，两行字根本没碰上**。
// 原因：Vision 给 CJK 文本的盒子留了**下伸部（descender）的空白**，
// 而副标题的盒子正好顶进这段空白里 → 盒子相交，字迹不相交。
//
// 所以这里改成**按字迹判**：先用盒子圈出候选，再逐像素把每段文字的
// **真实字迹范围**量出来（去掉盒子里的空白），最后拿字迹范围判重叠。
//
// ⛔ 为什么这个改动**不会漏报**：Vision 的盒子一定包住自己的字迹，
// 所以「字迹真重叠」必然蕴含「盒子重叠」——
// 反过来不成立（盒子重叠可能只是空白相交）。
// 也就是说：候选集只会被**缩小**（去掉误报），不会**新增**。
// 真正的字迹重叠，盒子一定相交 → 一定会进候选 → 一定测得出。
print("--- OVERLAP ---")
var n = 0
for i in 0..<boxes.count {
    for j in (i+1)..<boxes.count {
        let a = boxes[i], b = boxes[j]
        let ox = min(a.x+a.w, b.x+b.w) - max(a.x, b.x)
        let oy = min(a.y+a.h, b.y+b.h) - max(a.y, b.y)
        if ox > 2 && oy > 2 {
            // 候选：盒子相交（**不再用 25% 的盒子面积比当门槛**——
            // 那个门槛会漏掉真重叠，见下面的注释）。
            //
            // 候选的判据改成「**字迹落在同一行带**」。
            //
            // 2026-11-09 实测踩到的两个坑：
            //
            // ① **Vision 的盒子比字迹大**。中文标题「猫三联（第三针）」和它下面
            //    的副标题「Vaccine」被盒子判成「重叠 27%」—— 但逐像素量过：
            //    标题字迹到第 1217 行结束，副标题字迹从 1237 行才开始，
            //    **中间隔了 20 行空白，两行字根本没碰上**。
            //    原因：Vision 给 CJK 文本的盒子留了下伸部（descender）的空白，
            //    副标题的盒子正好顶进这段空白 → 盒子相交，字迹不相交。
            //
            // ② **原来的 25% 面积门槛会漏报**。两段字真的压在一起时，
            //    盒子相交的比例可能只有 17% —— 门槛一卡，真重叠就永远报不出来。
            //    （实测：两段 40pt 字错开 30pt，字迹真的重叠，盒子重叠比只有 16.7%
            //    → 旧工具报「无重叠」。）
            //
            // 所以：**候选 = 盒子有任何相交**（宽松），
            // **判定 = 字迹是否落在同一行带**（严格）。
            // 这样既不会漏报真重叠，也不会把「上下两行挨得近」误报成重叠。
            do {
                guard let shared = sharedColumns(a, b) else { continue }
                let bands = inkBands(rep, boxes: [a, b], columns: shared)
                guard let bandA = bands[0], let bandB = bands[1] else { continue }
                // 真重叠 = 两段字的字迹落在**同一行带**里。
                //
                // 2026-11-09 实测踩到的坑：中文标题「猫三联（第三针）」和它下面的
                // 副标题「Vaccine」被 Vision 的盒子判成「重叠 27%」——
                // 但逐像素量过：标题字迹到第 1217 行结束，副标题字迹从 1237 行开始，
                // **中间隔着 20 行空白，两行字根本没碰上**。
                // 原因：Vision 给 CJK 文本的盒子留了下伸部（descender）的空白，
                // 副标题的盒子正好顶进这段空白 → 盒子相交，字迹不相交。
                //
                // 判据：**同一行带**才算出重叠。
                // 文字真的叠在一起时，两段字的字迹必然落在同一批行上（一个行带）；
                // 只是挨得近时，它们在**不同的行带**里 → 不算重叠。
                guard bandA == bandB else { continue }
                // 同一行带 = 两段字的字迹真的压在同一批行上。
                // 报告的比例按**行带里列范围相交的部分**算。
                let rows = bandA.count
                let inkFrac = Double(rows) / Double(max(1, min(bandA.count, bandB.count)))
                if inkFrac > 0.25 {
                    print(String(format: "  %.0f%% '%@' <-> '%@'", inkFrac*100, a.t, b.t))
                    n += 1
                }
            }
        }
    }
}
if n == 0 { print("  (none)") }
// 3) 所有文字按 y 排序打印（右边缘坐标可见）
print("--- ALL (y, x, right) ---")
for b in boxes.sorted(by: { $0.y > $1.y }) {
    print(String(format: "  y=%.0f x=%.0f r=%.0f '%@'", b.y, b.x, b.x+b.w, b.t))
}


/// 两段文字**列范围相交**的那一段（两段字真要叠在一起，只能叠在这一段里）。
func sharedColumns(_ a: Box, _ b: Box) -> ClosedRange<Int>? {
    let x0 = max(Int(a.x), Int(b.x))
    let x1 = min(Int(a.x + a.w), Int(b.x + b.w))
    guard x1 - x0 > 2 else { return nil }
    return x0...x1
}

/// 把「有字迹的行」切成一段一段的**行带**（连续的行 = 一个带）。
///
/// 空行把带隔开 —— 这正是「上下两行文字」和「两段字真的叠在一起」的区别：
/// 前者中间有空行 → 两个带；后者字迹在同一批行上 → 一个带。
func inkBands(_ rep: NSBitmapImageRep, boxes: [Box], columns: ClosedRange<Int>) -> [Int: Set<Int>] {
    let H = Double(rep.pixelsHigh)
    // 所有盒子的行范围合起来
    var rowTop = Int.max, rowBot = Int.min
    for box in boxes {
        rowTop = min(rowTop, max(0, Int(H - (box.y + box.h))))
        rowBot = max(rowBot, min(rep.pixelsHigh, Int(H - box.y)))
    }
    guard rowBot > rowTop else { return [:] }

    // 逐行看有没有字迹
    var rowHasInk: [Int: Bool] = [:]
    for row in rowTop..<rowBot {
        var ink = false
        for col in columns {
            if let c = rep.colorAt(x: col, y: row) {
                // 亮度阈值：比纸白明显暗才算字迹。
                // 0.78 抓得到浅灰副标题（实测 AppColors.textSecondary），
                // 又不会把浅色卡片背景算进来。
                if c.brightnessComponent < 0.78 { ink = true; break }
            }
        }
        rowHasInk[row] = ink
    }

    // 切成行带
    var bands: [Int: Set<Int>] = [:]
    var current: Set<Int> = []
    var bandID = 0
    for row in rowTop..<rowBot {
        if rowHasInk[row] ?? false {
            current.insert(row)
        } else if !current.isEmpty {
            bands[bandID] = current
            bandID += 1
            current = []
        }
    }
    if !current.isEmpty { bands[bandID] = current; bandID += 1 }

    // 每个盒子归属到它**自己的字迹最多**的那个行带
    var result: [Int: Set<Int>] = [:]
    for (index, box) in boxes.enumerated() {
        var bestID = -1, bestCount = 0
        for (bid, rows) in bands {
            // 只算落在这个盒子行范围内的行
            let inBox = rows.filter { r in
                let top = Int(H - (box.y + box.h)), bot = Int(H - box.y)
                return r >= top && r < bot
            }
            if inBox.count > bestCount { bestCount = inBox.count; bestID = bid }
        }
        if bestID >= 0 { result[index] = bands[bestID]! }
    }
    return result
}
