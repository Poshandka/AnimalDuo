import Foundation
@main struct CloudSaveCheck {
    @MainActor static func settle(_ m:CloudSaveModel) async {
        for _ in 0..<1000 {
            if !m.busy{return}
            try! await Task.sleep(nanoseconds:1_000_000)
        }
        fatalError("Cloud model worker did not complete")
    }
    @MainActor static func main() async {
        let m=CloudSaveModel(),url=URL(fileURLWithPath:"/tmp/cloud-model-test/chosen",isDirectory:true)
        assert(!m.configured)
        m.choosingFolder=true;m.finishFolderSelection(url)
        assert(!m.choosingFolder && m.busy)
        // No modal-dismissal notification is delivered. Selection must still configure.
        await settle(m)
        assert(m.configured && m.folder=="chosen" && cloud_test_selects()==1)
        assert(cloud_test_inspections()==0 && cloud_test_prepares()==0 && cloud_test_sessions()==0)
        assert(m.message=="Cloud folder connected. Select Sync now to check your saves.")
        m.synchronize();await settle(m)
        assert(cloud_test_inspections()==1 && cloud_test_prepares()==1)
        m.choosingFolder=true;m.finishFolderSelection(nil)
        assert(!m.choosingFolder && !m.busy && m.configured && cloud_test_selects()==1)
        m.disconnect();assert(!m.configured)
        cloud_test_fail_selection(1);m.choosingFolder=true;m.finishFolderSelection(url);await settle(m)
        assert(!m.configured && !m.choosingFolder && m.message=="Selection failed.")
        assert(cloud_test_selects()==2 && cloud_test_inspections()==1)
        cloud_test_fail_selection(0)
        var played=false
        m.startPlay{played=true}
        assert(m.waitingForPlay && !played && !m.busy)
        m.choosingFolder=true;m.finishFolderSelection(url);await settle(m)
        assert(m.configured && m.waitingForPlay && !played && cloud_test_sessions()==0)
        m.synchronize();await settle(m)
        assert(played && !m.waitingForPlay && cloud_test_sessions()==1)
        print("cloud model: result delivery without dismissal, cancellation, bookmark error/retry and explicit synchronization passed")
    }
}
