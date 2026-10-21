import Testing
import WendyCore
import WendySwift

@Test
func `reports the linked Wendy Core version`() {
    #expect(!Wendy.coreVersion.isEmpty)
    #expect(Wendy.coreVersion == WendyCoreVersion())
}

@Test
func `reaches Wendy Core`() {
    #expect(Wendy.helloWorld() == 42)
}
