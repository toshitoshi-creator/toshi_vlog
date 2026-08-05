import SwiftUI

struct CameraView: View {
    @State private var camera = CameraViewModel()
    let videoLibrary: VideoLibrary

    var body: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            VStack {
                Spacer()

                if let error = camera.setupError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 16)
                }

                HStack {
                    Color.clear.frame(width: 56, height: 56)
                    Spacer()
                    recordButton
                    Spacer()
                    switchCameraButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .background(.black)
        .onAppear {
            camera.onVideoSaved = { url in
                Task { await videoLibrary.store(temporaryURL: url) }
            }
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
    }

    private var recordButton: some View {
        Button {
            camera.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                RoundedRectangle(cornerRadius: camera.isRecording ? 8 : 32)
                    .fill(.red)
                    .frame(
                        width: camera.isRecording ? 32 : 64,
                        height: camera.isRecording ? 32 : 64
                    )
                    .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
            }
        }
        .accessibilityLabel(camera.isRecording ? "録画を停止" : "録画を開始")
    }

    private var switchCameraButton: some View {
        Button {
            camera.switchCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.black.opacity(0.4), in: Circle())
        }
        .disabled(camera.isRecording)
    }
}
