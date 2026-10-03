import Testing
@testable import CosmicDaybook

extension Trait where Self == ConditionTrait {
    /// For tests of what the English sentence model gives. The model is a
    /// downloaded asset on the simulator, and a freshly made one (each
    /// checkout's leased simulator starts empty) has none, so there these show
    /// as skipped instead of failing on a missing model. The check waits out
    /// the simulator's lazy first load (`resolveTitleBackend`), so a runtime
    /// that has the model always runs them.
    static var needsSentenceModel: Self {
        .enabled("This runtime has no English sentence-embedding model") {
            await AlbumSemanticIndex.resolveTitleBackend() == "sentence"
        }
    }
}
