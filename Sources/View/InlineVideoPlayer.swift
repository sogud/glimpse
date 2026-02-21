//
//  InlineVideoPlayer.swift
//  PhotoSwipeCleaner
//
//  卡片内嵌视频播放器 - 支持手势穿透
//

import SwiftUI
import AVKit
import Photos

/// 使用 UIViewRepresentable 实现真正的手势穿透
struct InlineVideoPlayer: UIViewRepresentable {
    let asset: PHAsset
    @Binding var isPlaying: Bool

    func makeUIView(context: Context) -> VideoPlayerView {
        let view = VideoPlayerView()
        view.delegate = context.coordinator
        context.coordinator.view = view
        context.coordinator.loadVideo(asset: asset)
        return view
    }

    func updateUIView(_ uiView: VideoPlayerView, context: Context) {
        // 同步播放状态
        if isPlaying {
            uiView.play()
        } else {
            uiView.pause()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: InlineVideoPlayer
        weak var view: VideoPlayerView?

        init(_ parent: InlineVideoPlayer) {
            self.parent = parent
            super.init()
        }

        func loadVideo(asset: PHAsset) {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, info in
                DispatchQueue.main.async {
                    guard let avAsset = avAsset else {
                        return
                    }
                    self?.view?.setAsset(avAsset)
                }
            }
        }
    }
}

/// 自定义视频播放器视图 - 禁用所有手势拦截
class VideoPlayerView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerItem: AVPlayerItem?
    weak var delegate: InlineVideoPlayer.Coordinator?

    // 播放控制按钮
    private let playButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        btn.tintColor = .white
        btn.contentMode = .scaleAspectFit
        btn.isHidden = true
        return btn
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .black

        // 设置播放器层
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        self.playerLayer = layer
        self.layer.addSublayer(layer)

        // 添加播放按钮
        addSubview(playButton)
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)

        // 关键：禁用所有手势识别器，确保滑动可以穿透到父视图
        isUserInteractionEnabled = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds

        // 播放按钮居中
        let buttonSize: CGFloat = 60
        playButton.frame = CGRect(
            x: (bounds.width - buttonSize) / 2,
            y: (bounds.height - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )
        playButton.layer.cornerRadius = buttonSize / 2
    }

    /// 关键：重写 hitTest，让滑动事件穿透到父视图
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)

        // 如果点击的是播放按钮，正常响应
        if result == playButton {
            return playButton
        }

        // 其他区域返回 nil，让事件穿透到父视图
        return nil
    }

    func setAsset(_ asset: AVAsset) {
        // 清理旧的
        player?.pause()
        NotificationCenter.default.removeObserver(self)

        // 创建新的
        let item = AVPlayerItem(asset: asset)
        self.playerItem = item

        let player = AVPlayer(playerItem: item)
        self.player = player
        playerLayer?.player = player

        // 监听播放结束
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        // 自动播放
        player.play()
        playButton.isHidden = true
    }

    func play() {
        player?.play()
        playButton.isHidden = true
    }

    func pause() {
        player?.pause()
        playButton.isHidden = false
    }

    @objc private func togglePlay() {
        guard let player = player else { return }

        if player.rate > 0 {
            pause()
        } else {
            play()
        }
    }

    @objc private func playerDidFinishPlaying() {
        player?.seek(to: .zero)
        player?.play()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        player?.pause()
        player = nil
    }
}
