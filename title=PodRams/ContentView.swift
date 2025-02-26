private var toolbarContent: some ToolbarContent {
    Button(action: { isAudioOutputSelectionVisible.toggle() }) {
        Image(systemName: "airplayaudio")
    }

    Button(action: { isSubscribeVisible = true }) {
        Image(systemName: "rectangle.and.paperclip")
    }

    Button(action: { isFavoritesVisible = true }) {
        Image(systemName: "star")
    }

    Button(action: { if !cue.isEmpty { isCueVisible.toggle() } }) {
        Image(systemName: "list.bullet")
    }
} 