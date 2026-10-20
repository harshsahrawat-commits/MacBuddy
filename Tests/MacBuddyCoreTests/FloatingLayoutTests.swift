import Foundation
import MacBuddyCore

final class FloatingLayoutTests: CheckSuite {
    func testLegacyPreferencesAndNewOptions() throws {
        let old = Data("{\"backgroundOpacity\":1,\"positionLocked\":true,\"floatingPosition\":{\"screenID\":\"external\",\"horizontal\":0.73,\"vertical\":0.24}}".utf8)
        var prefs = try JSONDecoder().decode(OverlayPreferences.self, from: old)
        expectEqual(prefs.backgroundOpacity,1);expectTrue(prefs.positionLocked)
        expectEqual(prefs.floatingPosition?.screenID,"external");expectEqual(prefs.style,.strip);expectTrue(prefs.autoVertical)
        prefs.style = .avatar; prefs.dockedEdge = .right
        expectEqual(OverlayGeometry.layout(for:prefs),.avatar)
        let restored = try JSONDecoder().decode(OverlayPreferences.self,from:JSONEncoder().encode(prefs))
        expectEqual(restored,prefs)
        prefs.style = .strip
        expectEqual(OverlayGeometry.layout(for:prefs),.vertical)
        prefs.autoVertical = false
        expectEqual(OverlayGeometry.layout(for:prefs),.horizontal)
        let future = Data("{\"backgroundOpacity\":0.85,\"style\":\"future\",\"autoVertical\":\"future\",\"dockedEdge\":\"future\"}".utf8)
        let decoded = try JSONDecoder().decode(OverlayPreferences.self,from:future)
        expectEqual(decoded.backgroundOpacity,0.85);expectEqual(decoded.style,.strip);expectTrue(decoded.autoVertical)
    }
    func testEdgeDetectionAndOvershoot() {
        let screen = CGRect(x:-1600,y:200,width:1600,height:900)
        expectEqual(OverlayGeometry.nearbyEdge(of:CGRect(x:-1592,y:500,width:480,height:68),within:screen),.left)
        expectEqual(OverlayGeometry.nearbyEdge(of:CGRect(x:-488,y:500,width:480,height:68),within:screen),.right)
        expectEqual(OverlayGeometry.nearbyEdge(of:CGRect(x:-430,y:500,width:480,height:68),within:screen),.right)
        expectNil(OverlayGeometry.nearbyEdge(of:CGRect(x:-1100,y:500,width:480,height:68),within:screen))
    }
    func testAllAnchorsRoundTripAndExpand() {
        let screens = [CGRect(x:0,y:80,width:1470,height:840),CGRect(x:-1920,y:-500,width:1920,height:1080)]
        for screen in screens {
            for layout in [FloatingLayout.horizontal,.vertical,.avatar] {
                let anchor = OverlayGeometry.size(for:layout)
                for horizontal in [0.0,0.4,1] {
                    for vertical in [0.0,0.6,1] {
                        let position = FloatingPosition(screenID:"fixture",horizontal:horizontal,vertical:vertical)
                        let small = OverlayGeometry.frame(for:position,size:anchor,within:screen,anchorSize:anchor)
                        let saved = OverlayGeometry.position(for:small,screenID:"fixture",within:screen,anchorSize:anchor)
                        expectEqual(saved.horizontal,horizontal,accuracy:0.00001);expectEqual(saved.vertical,vertical,accuracy:0.00001)
                        let expanded = OverlayGeometry.frame(for:position,size:OverlayGeometry.expandedSize,within:screen,anchorSize:anchor)
                        expectTrue(screen.contains(expanded))
                        expectEqual(OverlayGeometry.frame(for:position,size:anchor,within:screen,anchorSize:anchor),small)
                        if horizontal == 1 { expectEqual(expanded.maxX,small.maxX) }
                    }
                }
            }
        }
    }
}
