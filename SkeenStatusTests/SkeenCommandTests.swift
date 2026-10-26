import Testing
import Foundation
@testable import SkeenStatus

@Suite("Skeen control and version parsing")
struct SkeenCommandTests {

    private let sample = """
    ------------------------------------------------
    SKeen: v4.0.3
    ------------------------------------------------
    Sing-box: v1.12.22
    Environment: go1.25.7 linux/arm64
    Tags: with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale
    Revision: f63091d14d8984d53dc9a5563cb72af978b9779e
    CGO: disabled
    """

    @Test func parsesAllVersionFields() {
        let v = parseSkeenVersion(sample)
        #expect(v.skeen == "v4.0.3")
        #expect(v.singBox == "v1.12.22")
        #expect(v.environment == "go1.25.7 linux/arm64")
        #expect(v.tags == "with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale")
        #expect(v.revision == "f63091d14d8984d53dc9a5563cb72af978b9779e")
        #expect(v.cgo == "disabled")
    }

    @Test func summaryCombinesSkeenAndSingBox() {
        let v = parseSkeenVersion(sample)
        #expect(v.summary == "SKeen v4.0.3 · Sing-box v1.12.22")
    }

    @Test func ignoresSurroundingNoiseAndCase() {
        let raw = "some prompt # \n  skeen: v4.0.3 \n garbage line\nSing-box:    v1.12.22\n"
        let v = parseSkeenVersion(raw)
        #expect(v.skeen == "v4.0.3")
        #expect(v.singBox == "v1.12.22")
    }

    @Test func emptyOutputYieldsEmptyVersion() {
        let v = parseSkeenVersion("------\n------\n")
        #expect(v.isEmpty)
        #expect(v.summary == "—")
    }

    @Test func controlSubcommandsMapToRawValues() {
        #expect(SkeenControl.start.rawValue == "start")
        #expect(SkeenControl.stop.rawValue == "stop")
        #expect(SkeenControl.restart.rawValue == "restart")
        #expect(SkeenControl.reload.rawValue == "reload")
    }

    @Test func onlyRestartAndReloadAreDisruptive() {
        #expect(SkeenControl.start.isDisruptive == false)
        #expect(SkeenControl.stop.isDisruptive == false)
        #expect(SkeenControl.restart.isDisruptive)
        #expect(SkeenControl.reload.isDisruptive)
    }
}
