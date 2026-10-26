import Testing
import Foundation
@testable import SkeenStatus

@Suite("sing-box Clash API")
struct SingBoxTests {

    @Test func groupsKeepSelectorsFirstAndHideGlobal() {
        let proxies: [String: ClashProxy] = [
            "GLOBAL": ClashProxy(type: "Fallback", name: "GLOBAL", now: "direct", all: ["proxy"]),
            "auto": ClashProxy(type: "URLTest", name: "auto", now: "NL", all: ["NL", "FI"]),
            "proxy": ClashProxy(type: "Selector", name: "proxy", now: "auto", all: ["auto", "direct"]),
            "NL": ClashProxy(type: "VLESS", name: "NL", now: nil, all: nil),
            "direct": ClashProxy(type: "Direct", name: "direct", now: nil, all: nil),
        ]
        let groups = outboundGroups(from: proxies)
        #expect(groups.map(\.name) == ["proxy", "auto"])
        #expect(groups[0].isSelectable)
        #expect(groups[1].isSelectable == false)
        #expect(groups[0].options == ["auto", "direct"])
    }

    @Test func modeNamesInRussian() {
        #expect(modeTitle("rule") == "По правилам")
        #expect(modeTitle("Global") == "Всё через прокси")
        #expect(modeTitle("direct") == "Всё напрямую")
        #expect(modeTitle("custom") == "custom")
    }

    @Test func endpointFollowsTheGatewayUnlessOverridden() {
        var config = Config.default
        config.gateway = "10.1.1.1"
        #expect(ClashEndpoint(config: config, secret: nil)?.baseURL.absoluteString == "http://10.1.1.1:9090")

        config.clashAPIURL = " https://router.lan:9443 "
        #expect(ClashEndpoint(config: config, secret: "s")?.baseURL.absoluteString == "https://router.lan:9443")
        #expect(ClashEndpoint(config: config, secret: "s")?.secret == "s")

        config.clashAPIEnabled = false
        #expect(ClashEndpoint(config: config, secret: nil) == nil)
    }

    @Test func brokenURLTurnsTheAPIOff() {
        var config = Config.default
        config.clashAPIURL = "not a url"
        #expect(ClashEndpoint(config: config, secret: nil) == nil)
    }
}
