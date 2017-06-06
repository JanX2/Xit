import XCTest
@testable import Xit

class XTEmptyRepositoryTest: XTTest
{
  override func addInitialRepoContent()
  {
  }

  func testEmptyRepositoryHead()
  {
    XCTAssertFalse(repository.hasHeadReference())
    XCTAssertEqual(repository.parentTree(), kEmptyTreeHash)
  }
  
  func testIsTextFile()
  {
    let textFiles = ["COPYING", "a.txt", "a.c", "a.xml", "a.html"]
    let nonTextFiles = ["a.jpg", "a.png", "a.ffff", "AAAAA"]
    
    for name in textFiles {
      XCTAssertTrue(repository.isTextFile(name, commit: "master"),
                    "\(name) should be a text file")
    }
    for name in nonTextFiles {
      XCTAssertFalse(repository.isTextFile(name, commit: "master"),
                     "\(name) should not be a text file")
    }
  }
  
  func testStagedContents()
  {
    let content = "some content"
    
    writeText(toFile1: content)
    XCTAssertNil(repository.contentsOfStagedFile(path: file1Name))
    try! repository.stage(file: file1Name)
    
    let expectedContent = content.data(using: .utf8)
    let stagedContent = repository.contentsOfStagedFile(path: file1Name)!
    let stagedString = String(data: stagedContent, encoding: .utf8)
    
    XCTAssertEqual(stagedContent, expectedContent)
    XCTAssertEqual(stagedString, content)
    
    // Write to the workspace file, but don't stage it. The staged content
    // should be the same.
    let newContent = "new stuff"
    
    writeText(toFile1: newContent)
    
    let stagedContent2 = repository.contentsOfStagedFile(path: file1Name)!
    let stagedString2 = String(data: stagedContent, encoding: .utf8)
    
    XCTAssertEqual(stagedContent2, expectedContent)
    XCTAssertEqual(stagedString2, content)
  }
}

class XTRepositoryTest: XTTest
{
  func assertWriteSucceeds(name: String, _ block: () throws -> Void)
  {
    do {
      try block()
    }
    catch XTRepository.Error.alreadyWriting {
      XCTFail("\(name): write unexpectedly failed")
    }
    catch {
      XCTFail("\(name): unexpected exception")
    }
  }
  
  func assertWriteFails(name: String, block: () throws -> Void)
  {
    do {
      try block()
      XCTFail("\(name): write unexpectedly succeeded")
    }
    catch XTRepository.Error.alreadyWriting {
    }
    catch {
      XCTFail("\(name): unexpected exception")
    }
  }
  
  func assertWriteException(name: String, block: () throws -> Void)
  {
    setRepoWriting(repository, true)
    assertWriteFails(name: name, block: block)
    setRepoWriting(repository, false)
    assertWriteSucceeds(name: name, block)
  }
  
  func assertWriteBool(name: String, block: () -> Bool)
  {
    setRepoWriting(repository, true)
    XCTAssertFalse(block(), "\(name) writing")
    setRepoWriting(repository, false)
    XCTAssertTrue(block(), "\(name) non-writing")
  }

  func testWriteLockStage()
  {
    writeText(toFile1: "modification")
    
    assertWriteException(name: "stageFile") {
      try repository.stage(file: file1Name)
    }
    assertWriteException(name: "unstageFile") {
      try repository.unstage(file: file1Name)
    }
  }
  
  func testWriteLockStash()
  {
    writeText(toFile1: "modification")

    assertWriteException(name: "unstageFile") {
      try repository.saveStash(name: "stashname", includeUntracked: false)
    }
    assertWriteException(name: "apply") { try repository.applyStash(index: 0) }
    assertWriteException(name: "drop") { try repository.dropStash(index: 0) }
    writeText(toFile1: "modification")
    try! repository.saveStash(name: "stashname", includeUntracked: false)
    assertWriteException(name: "pop") { try repository.popStash(index: 0) }
  }
  
  func testWriteLockCommit()
  {
    writeText(toFile1: "modification")
    try! repository.stage(file: file1Name)
    
    assertWriteException(name: "commit") { 
      try repository.commit(message: "blah", amend: false, outputBlock: nil)
    }
  }
  
  func testWriteLockBranches()
  {
    let masterBranch = "master"
    let testBranch1 = "testBranch1"
    let testBranch2 = "testBranch2"
    
    assertWriteBool(name: "create") { repository.createBranch(testBranch1) }
    assertWriteException(name: "rename") {
      try repository.rename(branch: testBranch1, to: testBranch2)
    }
    assertWriteException(name: "checkout") {
      try repository.checkout(branch: masterBranch)
    }
    assertWriteBool(name: "delete") {
      repository.deleteBranch(testBranch2)
    }
  }
  
  func testWriteLockTags()
  {
    assertWriteException(name: "create") {
      try repository.createTag(name: "tag", targetSHA: repository.headSHA!, message: "msg")
    }
    assertWriteException(name: "delete") {
      try repository.deleteTag(name: "tag")
    }
  }
  
  func testWriteRemotes()
  {
    let testRemoteName1 = "remote1"
    let testRemoteName2 = "remote2"
    
    assertWriteException(name: "add") {
      try repository.add(remote: testRemoteName1,
                         url: URL(fileURLWithPath: "fakeurl"))
    }
    assertWriteException(name: "rename") {
      try repository.renameRemote(old: testRemoteName1, new: testRemoteName2)
    }
    assertWriteException(name: "delete") {
      try repository.delete(remote: testRemoteName2)
    }
  }

  func testHeadRef()
  {
    XCTAssertEqual(repository.headRef, "refs/heads/master")
    
    guard let headSHA = repository.headSHA
    else {
      XCTFail("no head SHA")
      return
    }
    let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
    
    XCTAssertEqual(headSHA.utf8.count, 40)
    XCTAssertTrue(headSHA.trimmingCharacters(in: hexChars).isEmpty)
  }
  
  func testDetachedCheckout()
  {
    guard let firstSHA = repository.headSHA
    else {
      XCTFail("no head SHA")
      return
    }
    
    try! "mash".write(toFile: file1Path, atomically: true, encoding: .utf8)
    try! repository.stage(file: file1Name)
    try! repository.checkout(sha: firstSHA)
    
    guard let detachedSHA = repository.headSHA
    else {
      XCTFail("no detached head SHA")
      return
    }
    
    XCTAssertEqual(firstSHA, detachedSHA)
  }
  
  func testContents()
  {
    guard let headSHA = repository.headSHA,
          let headCommit = XTCommit(sha: headSHA, repository: repository)
    else {
        XCTFail("no head SHA")
        return
    }
    let contentData = repository.contentsOfFile(path: file1Name,
                                                at: headCommit)!
    let contentString = String(data: contentData, encoding: .utf8)
    
    XCTAssertEqual(contentString, "some text")
  }

  func checkDeletedDiff(_ diff: XTDiffDelta?)
  {
    guard let diff = diff
      else {
        XCTFail("diff is null")
        return
    }
    guard let patch = try? diff.generatePatch()
      else {
        XCTFail("patch is null")
        return
    }
    
    XCTAssertEqual(patch.hunkCount, 1)
    XCTAssertEqual(patch.addedLinesCount, 0)
    XCTAssertEqual(patch.deletedLinesCount, 1)
    patch.enumerateHunks {
      (hunk, stop) in
      try! hunk.enumerateLinesInHunk(usingBlock: {
        (line, stop) in
        switch line.origin {
          case .deletion:
            XCTAssertEqual(line.content, "some text")
          default:
            break
        }
      })
    }
  }
  
  func testAddedChange()
  {
    let changes = repository.changes(for: "master", parent: nil)
    
    XCTAssertEqual(changes.count, 1)
    
    let change = changes[0]
    
    XCTAssertEqual(change.path, file1Name)
    XCTAssertEqual(change.change, XitChange.added)
  }
  
  func testModifiedChange()
  {
    let file2Name = "file2.txt"
    let file2Path = repoPath.appending(pathComponent: file2Name)
    
    writeText(toFile1: "changes!")
    try! "new file 2".write(toFile: file2Path, atomically: true, encoding: .utf8)
    try! repository.stage(file: file1Name)
    try! repository.stage(file: file2Name)
    try! repository.commit(message: "#2", amend: false, outputBlock: nil)
    
    let changes2 = repository.changes(for: "master", parent: nil)
    
    XCTAssertEqual(changes2.count, 2)
    
    let file1Change = changes2[0]
    
    XCTAssertEqual(file1Change.path, file1Name)
    XCTAssertEqual(file1Change.change, .modified)
    
    let file2Change = changes2[1]
    
    XCTAssertEqual(file2Change.path, file2Name)
    XCTAssertEqual(file2Change.change, .added)
  }
  
  func testDeletedChange()
  {
    try! FileManager.default.removeItem(atPath: file1Path)
    try! repository.stage(file: file1Name)
    try! repository.commit(message: "#3", amend: false, outputBlock: nil)
    
    let changes3 = repository.changes(for: "master", parent: nil)
    
    XCTAssertEqual(changes3.count, 1)
    
    let file1Deleted = changes3[0]
    
    XCTAssertEqual(file1Deleted.path, file1Name)
    XCTAssertEqual(file1Deleted.change, .deleted)
  }
  
  func testStageUnstageAllStatus()
  {
    let file2Name = "file2.txt"
    let file3Name = "file3.txt"
    
    commitNewTextFile(file2Name, content: "blah")
    
    let file2Path = repoPath.appending(pathComponent: file2Name)
    let file3Path = repoPath.appending(pathComponent: file3Name)
    
    try! "blah".write(toFile: file1Path, atomically: true, encoding: .utf8)
    try! FileManager.default.removeItem(atPath: file2Path)
    try! "blah".write(toFile: file3Path, atomically: true, encoding: .utf8)
    try! repository.stageAllFiles()
    
    var changes = repository.changes(for: XTStagingSHA, parent: nil)
    
    XCTAssertEqual(changes.count, 3);
    XCTAssertEqual(changes[0].unstagedChange, XitChange.unmodified); // file1
    XCTAssertEqual(changes[0].change, XitChange.modified);
    XCTAssertEqual(changes[1].unstagedChange, XitChange.unmodified); // file2
    XCTAssertEqual(changes[1].change, XitChange.deleted);
    XCTAssertEqual(changes[2].unstagedChange, XitChange.unmodified); // file3
    XCTAssertEqual(changes[2].change, XitChange.added);
    
    try! repository.unstageAllFiles()
    changes = repository.changes(for: XTStagingSHA, parent: nil)
    
    XCTAssertEqual(changes.count, 3);
    XCTAssertEqual(changes[0].unstagedChange, XitChange.modified); // file1
    XCTAssertEqual(changes[0].change, XitChange.unmodified);
    XCTAssertEqual(changes[1].unstagedChange, XitChange.deleted); // file2
    XCTAssertEqual(changes[1].change, XitChange.unmodified);
    XCTAssertEqual(changes[2].unstagedChange, XitChange.untracked); // file3
    XCTAssertEqual(changes[2].change, XitChange.unmodified);
  }

  func testDeleteDiff()
  {
    try? FileManager.default.removeItem(atPath: file1Path)
    checkDeletedDiff(repository.unstagedDiff(file: file1Name)!.makeDiff())
    
    try! repository.stage(file: file1Name)
    checkDeletedDiff(repository.stagedDiff(file: file1Name)!.makeDiff())
  }
  
  func testDeletedDiff()
  {
    try! FileManager.default.removeItem(atPath: file1Path)
    try! repository.stage(file: file1Name)
    try! repository.commit(message: "deleted", amend: false,
                           outputBlock: nil)
    
    guard let commit = XTCommit(ref: "HEAD", repository: repository)
    else {
      XCTFail("no HEAD")
      return
    }
    
    let parentSHA = commit.parentSHAs.first!
    let maker = repository.diffMaker(forFile: file1Name,
                                     commitSHA: commit.sha!,
                                     parentSHA: parentSHA)!
    let diff = maker.makeDiff()!
    let patch = try! diff.generatePatch()
    
    XCTAssertEqual(patch.deletedLinesCount, 1)
  }
  
  func testAddedDiff()
  {
    guard let commit = XTCommit(ref: "HEAD", repository: repository)
    else {
      XCTFail("no HEAD")
      return
    }
    
    let maker = repository.diffMaker(forFile: file1Name,
                                     commitSHA: commit.sha!,
                                     parentSHA: nil)!
    let diff = maker.makeDiff()!
    let patch = try! diff.generatePatch()
    
    XCTAssertEqual(patch.addedLinesCount, 1)
  }
}

class XTRepositoryHunkTest: XTTest
{
  let testBundle = Bundle(identifier: "com.uncommonplace.XitTests")!
  let loremName = "lorem.txt"
  var loremURL, lorem2URL: URL!
  var loremRepoURL: URL!

  override func setUp()
  {
    super.setUp()
    loremURL = testBundle.url(forResource: "lorem", withExtension: "txt")!
    lorem2URL = testBundle.url(forResource: "lorem2", withExtension: "txt")!
    loremRepoURL = repository.repoURL.appendingPathComponent(loremName)
  }
  
  /// Returns the content of lorem.txt in the index
  func readLoremIndexText() -> String?
  {
    var encoding = String.Encoding.utf8
    guard let indexData = repository.stagedBlob(file: loremName)?.data()
    else { return nil }
    
    return String(data: indexData, usedEncoding: &encoding)
  }
  
  /// Copies the test bundle's lorem2.txt into the repo's lorem.txt
  func copyLorem2Contents() throws
  {
    let lorem2Data = try! Data(contentsOf: lorem2URL)
    
    try! lorem2Data.write(to: loremRepoURL)
  }
  
  /// Tests staging the first hunk of a changed file
  func testStageHunk()
  {
    try! FileManager.default.copyItem(at: loremURL, to: loremRepoURL)
    try! repository.stage(file: loremName)
    try! copyLorem2Contents()
    
    let diffMaker = repository.unstagedDiff(file: loremName)!
    let diff = diffMaker.makeDiff()!
    let patch = try! diff.generatePatch()
    let hunk = GTDiffHunk(patch: patch, hunkIndex: 0)!
    
    try! repository.patchIndexFile(path: loremName, hunk: hunk, stage: true)
    
    let indexText = readLoremIndexText()!

    XCTAssert(indexText.hasPrefix(
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec nec maximus mauris. Quisque varius nisi ac augue rutrum ullamcorper. Sed tincidunt leo in erat commodo, tempor ultricies quam sagittis.\n" +
          "Duis risus quam, malesuada vel ante at, tincidunt sagittis erat. Phasellus a ante erat. Donec tristique lorem leo, sit amet congue est convallis vitae. Vestibulum a faucibus nisl. Pellentesque vitae sem vitae enim pharetra lacinia.\n" +
        "Pellentesque mattis ante eget dignissim cursus. Nullam lacinia sit amet sapien ac feugiat. Aenean sagittis eros dignissim volutpat faucibus. Proin laoreet tempus nunc in suscipit.\n\n"))
  }
  
  /// Tests unstaging the first hunk of a staged file
  func testUnstageHunk()
  {
    try! FileManager.default.copyItem(at: loremURL, to: loremRepoURL)
    try! repository.stage(file: loremName)
    try! repository.commit(message: "lorem", amend: false, outputBlock: nil)
    try! copyLorem2Contents()
    try! repository.stage(file: loremName)
    
    let diffMaker = repository.stagedDiff(file: loremName)!
    let diff = diffMaker.makeDiff()!
    let patch = try! diff.generatePatch()
    let hunk = GTDiffHunk(patch: patch, hunkIndex: 0)!
    
    try! repository.patchIndexFile(path: loremName, hunk: hunk, stage: false)
    
    let indexText = readLoremIndexText()!
    
    XCTAssert(indexText.hasPrefix(
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec nec maximus mauris. Quisque varius nisi ac augue rutrum ullamcorper. Sed tincidunt leo in erat commodo, tempor ultricies quam sagittis.\n" +
        "Duis risus quam, malesuada vel ante at, tincidunt sagittis erat. Phasellus a ante erat. Donec tristique lorem leo, sit amet congue est convallis vitae. Vestibulum a faucibus nisl. Pellentesque vitae sem vitae enim pharetra lacinia.\n" +
        "Pellentesque mattis ante eget dignissim cursus. Nullam lacinia sit amet sapien ac feugiat. Aenean sagittis eros dignissim volutpat faucibus. Proin laoreet tempus nunc in suscipit.\n" +
        "Cras vestibulum id neque eu imperdiet. Pellentesque a lacus ipsum. Nulla ultrices consectetur congue.\n"))
  }
  
  /// Tests staging a new file as a hunk
  func testStageNewHunk()
  {
    try! FileManager.default.copyItem(at: loremURL, to: loremRepoURL)
    
    let diffMaker = repository.unstagedDiff(file: loremName)!
    let diff = diffMaker.makeDiff()!
    let patch = try! diff.generatePatch()
    let hunk = GTDiffHunk(patch: patch, hunkIndex: 0)!

    try! repository.patchIndexFile(path: loremName, hunk: hunk, stage: true)
    
    var encoding = String.Encoding.utf8
    let stagedText = readLoremIndexText()!
    let loremData = try! Data(contentsOf: loremURL)
    let loremText = String(data: loremData, usedEncoding: &encoding)!
    
    XCTAssertEqual(stagedText, loremText)
  }
  
  /// Tests staging a deleted file as a hunk
  func testStageDeletedHunk()
  {
    try! FileManager.default.removeItem(atPath: file1Path)

    let diffMaker = repository.unstagedDiff(file: file1Name)!
    let diff = diffMaker.makeDiff()!
    let patch = try! diff.generatePatch()
    let hunk = GTDiffHunk(patch: patch, hunkIndex: 0)!
    
    try! repository.patchIndexFile(path: file1Name, hunk: hunk, stage: true)
    
    let status = try! repository.status(file: file1Name)
    
    XCTAssertEqual(status.0, XitChange.unmodified)
    XCTAssertEqual(status.1, XitChange.deleted)
  }
  
  /// Tests unstaging a new file as a hunk
  func testUnstageNewHunk()
  {
    try! FileManager.default.copyItem(at: loremURL, to: loremRepoURL)
    try! repository.stage(file: loremName)
    
    let diffMaker = repository.stagedDiff(file: loremName)!
    let diff = diffMaker.makeDiff()!
    let patch = try! diff.generatePatch()
    let hunk = GTDiffHunk(patch: patch, hunkIndex: 0)!
    
    try! repository.patchIndexFile(path: loremName, hunk: hunk, stage: false)
    
    let status = try! repository.status(file: loremName)
    
    XCTAssertEqual(status.0, XitChange.untracked)
    XCTAssertEqual(status.1, XitChange.unmodified) // There is no "absent"
  }
  
  /// Tests unstaging a deleted file as a hunk
  func testUnstageDeletedHunk()
  {
    try! FileManager.default.removeItem(atPath: file1Path)
    try! repository.stage(file: file1Name)
    
    let diffMaker = repository.stagedDiff(file: file1Name)!
    let diff = diffMaker.makeDiff()!
    let patch = try! diff.generatePatch()
    let hunk = GTDiffHunk(patch: patch, hunkIndex: 0)!
    
    try! repository.patchIndexFile(path: file1Name, hunk: hunk, stage: false)
    
    let status = try! repository.status(file: file1Name)
    
    XCTAssertEqual(status.0, XitChange.deleted)
    XCTAssertEqual(status.1, XitChange.unmodified)
  }
}
