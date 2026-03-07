//
//  InlineVideoPlayer.swift
//  PhotoSwipeCleaner
//
//  卡片内嵌视频播放器 - 支持多平台
//

import SwiftUI
import AVKit
import Photos

#if canImport(UIKit)
import UIKit

/// 使用 UIViewRepresentable 实现真正的手势穿透
struct InlineVideoPlayer: UIViewRepresentable {
    let asset: PHAsset
    @Binding var isPlaying: Bool
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> VideoPlayerView {
        let view = VideoPlayerView()
        view.delegate = context.coordinator
        context.coordinator.view = view
        context.coordinator.loadVideo(asset: asset)
        return view
    }

    func updateUIView(_ uiView: VideoPlayerView, context: Context) {
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
        private var requestID: PHImageRequestID = PHInvalidImageRequestID

        init(_ parent: InlineVideoPlayer) {
            self.parent = parent
            super.init()
        }

        func loadVideo(asset: PHAsset) {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            DispatchQueue.main.async {
                self.parent.isLoading = true
            }

            if requestID != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }

            requestID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.requestID = PHInvalidImageRequestID

                    guard let avAsset else {
                        self.parent.isLoading = false
                        self.parent.isPlaying = false
                        return
                    }

                    guard self.parent.isPlaying else {
                        self.parent.isLoading = false
                        return
                    }

                    self.view?.setAsset(avAsset)
                    self.parent.isLoading = false
                }
            }
        }

        deinit {
            if requestID != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(requestID)
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

        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        self.playerLayer = layer
        self.layer.addSublayer(layer)

        addSubview(playButton)
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        isUserInteractionEnabled = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds

        let buttonSize: CGFloat = 60
        playButton.frame = CGRect(
            x: (bounds.width - buttonSize) / 2,
            y: (bounds.height - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )
        playButton.layer.cornerRadius = buttonSize / 2
    }

    /// 让非按钮区域的事件穿透，避免阻断父层滑动
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        if result == playButton {
            return playButton
        }
        return nil
    }

    func setAsset(_ asset: AVAsset) {
        player?.pause()
        NotificationCenter.default.removeObserver(self)

        let item = AVPlayerItem(asset: asset)
        self.playerItem = item

        let player = AVPlayer(playerItem: item)
        self.player = player
        playerLayer?.player = player

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

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
        guard let player else { return }
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

#else

/// 非 UIKit 平台回退实现：使用系统 VideoPlayer
struct InlineVideoPlayer: View {
    let asset: PHAsset
    @Binding var isPlaying: Bool
    @Binding var isLoading: Bool

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onChange(of: isPlaying) { _, newValue in
                        if newValue {
                            player.play()
                        } else {
                            player.pause()
                        }
                    }
            } else {
                ProgressView()
                    .onAppear {
                        isLoading = true
                        loadVideo()
                    }
            }
        }
    }

    private func loadVideo() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            DispatchQueue.main.async {
                guard let avAsset else {
                    isLoading = false
                    isPlaying = false
                    return
                }

                guard isPlaying else {
                    isLoading = false
                    return
                }

                let player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
                self.player = player
                isLoading = false
                if isPlaying {
                    player.play()
                }
            }
        }
    }
}

#endif
