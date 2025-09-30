/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The profile image that reflects the selected item state.
*/

import SwiftUI
import PhotosUI

struct ProfileImage: View {
	let imageState: ProfileImageModel.ImageState

	var body: some View {
		switch imageState {
		case .success(let image):
			image.resizable()
		case .loading:
			ProgressView()
		case .empty:
			Image(systemName: "person.fill")
				.font(.system(size: 40))
				.foregroundColor(.white)
		case .failure:
			Image(systemName: "exclamationmark.triangle.fill")
				.font(.system(size: 40))
				.foregroundColor(.white)
		}
	}
}

struct CircularProfileImage: View {
	let imageState: ProfileImageModel.ImageState
    var size: CGFloat = 60

	var body: some View {
		ProfileImage(imageState: imageState)
            .scaledToFill()
			.clipShape(Circle())
			.frame(width: size, height: size)
			.background {
				Circle().fill(
					LinearGradient(
						colors: [.yellow, .orange],
						startPoint: .top,
						endPoint: .bottom
					)
				)
			}
	}
}

struct EditableCircularProfileImage: View {
	@ObservedObject var model: ProfileImageModel
    var size: CGFloat = 30

	var body: some View {
		CircularProfileImage(imageState: model.imageState)
			.overlay(alignment: .bottomTrailing) {
				PhotosPicker(selection: $model.imageSelection,
							 matching: .images
                ) {
					Image(systemName: "pencil.circle.fill")
						.symbolRenderingMode(.multicolor)
						.font(.system(size: size))
						.foregroundColor(.accentColor)
				}
				.buttonStyle(.borderless)
			}
	}
}
