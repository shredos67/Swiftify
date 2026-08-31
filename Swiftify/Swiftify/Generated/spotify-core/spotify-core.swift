public func core_version() -> RustString {
    RustString(ptr: __swift_bridge__$core_version())
}

public class SpotifyCore: SpotifyCoreRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$SpotifyCore$_free(ptr)
        }
    }
}
extension SpotifyCore {
    public convenience init() {
        self.init(ptr: __swift_bridge__$SpotifyCore$new())
    }
}
public class SpotifyCoreRefMut: SpotifyCoreRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class SpotifyCoreRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension SpotifyCoreRef {
    public func connect<GenericIntoRustString: IntoRustString>(_ access_token: GenericIntoRustString, _ client_id: GenericIntoRustString) async throws -> () {
        func onComplete(cbWrapperPtr: UnsafeMutableRawPointer?, rustFnRetVal: UnsafeMutableRawPointer?) {
            let wrapper = Unmanaged<CbWrapper$SpotifyCore$connect>.fromOpaque(cbWrapperPtr!).takeRetainedValue()
            if rustFnRetVal == nil {
                wrapper.cb(.success(()))
            } else {
                wrapper.cb(.failure(RustString(ptr: rustFnRetVal!)))
            }
        }

        return try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<(), Error>) in
            let callback = { rustFnRetVal in
                continuation.resume(with: rustFnRetVal)
            }

            let wrapper = CbWrapper$SpotifyCore$connect(cb: callback)
            let wrapperPtr = Unmanaged.passRetained(wrapper).toOpaque()

            __swift_bridge__$SpotifyCore$connect(wrapperPtr, onComplete, ptr, { let rustString = access_token.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = client_id.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
        })
    }
    class CbWrapper$SpotifyCore$connect {
        var cb: (Result<(), Error>) -> ()
    
        public init(cb: @escaping (Result<(), Error>) -> ()) {
            self.cb = cb
        }
    }

    public func play_track<GenericIntoRustString: IntoRustString>(_ spotify_uri: GenericIntoRustString) async throws -> () {
        func onComplete(cbWrapperPtr: UnsafeMutableRawPointer?, rustFnRetVal: UnsafeMutableRawPointer?) {
            let wrapper = Unmanaged<CbWrapper$SpotifyCore$play_track>.fromOpaque(cbWrapperPtr!).takeRetainedValue()
            if rustFnRetVal == nil {
                wrapper.cb(.success(()))
            } else {
                wrapper.cb(.failure(RustString(ptr: rustFnRetVal!)))
            }
        }

        return try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<(), Error>) in
            let callback = { rustFnRetVal in
                continuation.resume(with: rustFnRetVal)
            }

            let wrapper = CbWrapper$SpotifyCore$play_track(cb: callback)
            let wrapperPtr = Unmanaged.passRetained(wrapper).toOpaque()

            __swift_bridge__$SpotifyCore$play_track(wrapperPtr, onComplete, ptr, { let rustString = spotify_uri.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
        })
    }
    class CbWrapper$SpotifyCore$play_track {
        var cb: (Result<(), Error>) -> ()
    
        public init(cb: @escaping (Result<(), Error>) -> ()) {
            self.cb = cb
        }
    }

    public func load_track<GenericIntoRustString: IntoRustString>(_ spotify_uri: GenericIntoRustString) throws -> () {
        try { let val = __swift_bridge__$SpotifyCore$load_track(ptr, { let rustString = spotify_uri.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); if val != nil { throw RustString(ptr: val!) } else { return } }()
    }

    public func play() throws -> () {
        try { let val = __swift_bridge__$SpotifyCore$play(ptr); if val != nil { throw RustString(ptr: val!) } else { return } }()
    }

    public func pause() throws -> () {
        try { let val = __swift_bridge__$SpotifyCore$pause(ptr); if val != nil { throw RustString(ptr: val!) } else { return } }()
    }

    public func seek(_ position_ms: UInt32) throws -> () {
        try { let val = __swift_bridge__$SpotifyCore$seek(ptr, position_ms); if val != nil { throw RustString(ptr: val!) } else { return } }()
    }

    public func playback_position_ms() -> UInt32 {
        __swift_bridge__$SpotifyCore$playback_position_ms(ptr)
    }

    public func playback_duration_ms() -> UInt32 {
        __swift_bridge__$SpotifyCore$playback_duration_ms(ptr)
    }

    public func take_end_of_track() -> Bool {
        __swift_bridge__$SpotifyCore$take_end_of_track(ptr)
    }

    public func is_playing_local() -> Bool {
        __swift_bridge__$SpotifyCore$is_playing_local(ptr)
    }

    public func set_downloads_directory<GenericIntoRustString: IntoRustString>(_ directory: GenericIntoRustString) throws -> () {
        try { let val = __swift_bridge__$SpotifyCore$set_downloads_directory(ptr, { let rustString = directory.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); if val != nil { throw RustString(ptr: val!) } else { return } }()
    }

    public func download_track<GenericIntoRustString: IntoRustString>(_ spotify_uri: GenericIntoRustString) async throws -> () {
        func onComplete(cbWrapperPtr: UnsafeMutableRawPointer?, rustFnRetVal: UnsafeMutableRawPointer?) {
            let wrapper = Unmanaged<CbWrapper$SpotifyCore$download_track>.fromOpaque(cbWrapperPtr!).takeRetainedValue()
            if rustFnRetVal == nil {
                wrapper.cb(.success(()))
            } else {
                wrapper.cb(.failure(RustString(ptr: rustFnRetVal!)))
            }
        }

        return try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<(), Error>) in
            let callback = { rustFnRetVal in
                continuation.resume(with: rustFnRetVal)
            }

            let wrapper = CbWrapper$SpotifyCore$download_track(cb: callback)
            let wrapperPtr = Unmanaged.passRetained(wrapper).toOpaque()

            __swift_bridge__$SpotifyCore$download_track(wrapperPtr, onComplete, ptr, { let rustString = spotify_uri.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
        })
    }
    class CbWrapper$SpotifyCore$download_track {
        var cb: (Result<(), Error>) -> ()
    
        public init(cb: @escaping (Result<(), Error>) -> ()) {
            self.cb = cb
        }
    }

    public func track_available_locally<GenericIntoRustString: IntoRustString>(_ spotify_uri: GenericIntoRustString) -> Bool {
        __swift_bridge__$SpotifyCore$track_available_locally(ptr, { let rustString = spotify_uri.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
    }

    public func downloaded_track_uris() -> RustVec<RustString> {
        RustVec(ptr: __swift_bridge__$SpotifyCore$downloaded_track_uris(ptr))
    }

    public func remove_download<GenericIntoRustString: IntoRustString>(_ spotify_uri: GenericIntoRustString) -> Bool {
        __swift_bridge__$SpotifyCore$remove_download(ptr, { let rustString = spotify_uri.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
    }

    public func play_local_track<GenericIntoRustString: IntoRustString>(_ spotify_uri: GenericIntoRustString) async throws -> () {
        func onComplete(cbWrapperPtr: UnsafeMutableRawPointer?, rustFnRetVal: UnsafeMutableRawPointer?) {
            let wrapper = Unmanaged<CbWrapper$SpotifyCore$play_local_track>.fromOpaque(cbWrapperPtr!).takeRetainedValue()
            if rustFnRetVal == nil {
                wrapper.cb(.success(()))
            } else {
                wrapper.cb(.failure(RustString(ptr: rustFnRetVal!)))
            }
        }

        return try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<(), Error>) in
            let callback = { rustFnRetVal in
                continuation.resume(with: rustFnRetVal)
            }

            let wrapper = CbWrapper$SpotifyCore$play_local_track(cb: callback)
            let wrapperPtr = Unmanaged.passRetained(wrapper).toOpaque()

            __swift_bridge__$SpotifyCore$play_local_track(wrapperPtr, onComplete, ptr, { let rustString = spotify_uri.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
        })
    }
    class CbWrapper$SpotifyCore$play_local_track {
        var cb: (Result<(), Error>) -> ()
    
        public init(cb: @escaping (Result<(), Error>) -> ()) {
            self.cb = cb
        }
    }

    public func set_volume(_ volume: Float) throws -> () {
        try { let val = __swift_bridge__$SpotifyCore$set_volume(ptr, volume); if val != nil { throw RustString(ptr: val!) } else { return } }()
    }

    public func volume() -> Float {
        __swift_bridge__$SpotifyCore$volume(ptr)
    }

    public func lyrics_json<GenericIntoRustString: IntoRustString>(_ spotify_uri: GenericIntoRustString) async throws -> RustString {
        func onComplete(cbWrapperPtr: UnsafeMutableRawPointer?, rustFnRetVal: __private__ResultPtrAndPtr) {
            let wrapper = Unmanaged<CbWrapper$SpotifyCore$lyrics_json>.fromOpaque(cbWrapperPtr!).takeRetainedValue()
            if rustFnRetVal.is_ok {
                wrapper.cb(.success(RustString(ptr: rustFnRetVal.ok_or_err!)))
            } else {
                wrapper.cb(.failure(RustString(ptr: rustFnRetVal.ok_or_err!)))
            }
        }

        return try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<RustString, Error>) in
            let callback = { rustFnRetVal in
                continuation.resume(with: rustFnRetVal)
            }

            let wrapper = CbWrapper$SpotifyCore$lyrics_json(cb: callback)
            let wrapperPtr = Unmanaged.passRetained(wrapper).toOpaque()

            __swift_bridge__$SpotifyCore$lyrics_json(wrapperPtr, onComplete, ptr, { let rustString = spotify_uri.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
        })
    }
    class CbWrapper$SpotifyCore$lyrics_json {
        var cb: (Result<RustString, Error>) -> ()
    
        public init(cb: @escaping (Result<RustString, Error>) -> ()) {
            self.cb = cb
        }
    }

    public func spectrum_levels() -> RustVec<Float> {
        RustVec(ptr: __swift_bridge__$SpotifyCore$spectrum_levels(ptr))
    }
}
extension SpotifyCore: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_SpotifyCore$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_SpotifyCore$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: SpotifyCore) {
        __swift_bridge__$Vec_SpotifyCore$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_SpotifyCore$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (SpotifyCore(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SpotifyCoreRef> {
        let pointer = __swift_bridge__$Vec_SpotifyCore$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SpotifyCoreRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SpotifyCoreRefMut> {
        let pointer = __swift_bridge__$Vec_SpotifyCore$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SpotifyCoreRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<SpotifyCoreRef> {
        UnsafePointer<SpotifyCoreRef>(OpaquePointer(__swift_bridge__$Vec_SpotifyCore$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_SpotifyCore$len(vecPtr)
    }
}



