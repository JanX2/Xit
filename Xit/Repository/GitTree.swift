import Foundation

public protocol Tree: OIDObject
{
  var count: Int { get }
  
  func entry(named: String) -> TreeEntry?
  func entry(path: String) -> TreeEntry?
  func entry(at index: Int) -> TreeEntry?
  func walkEntries(callback: (TreeEntry, String) -> Void)
}

public protocol TreeEntry: OIDObject
{
  var type: GitObjectType { get }
  var name: String { get }
  var object: OIDObject? { get }
}


/// Used as a return value when an entry can't be returned for a given subscript
struct NullEntry: TreeEntry
{
  var oid: OID
  { GitOID.zero() }
  var type: GitObjectType
  { .invalid }
  var name: String
  { "" }
  var object: OIDObject?
  { nil }
}

class GitTree: Tree
{
  struct EntryCollection: Collection
  {
    let tree: GitTree

    var startIndex: Int { 0 }
    var endIndex: Int { tree.count }
    
    func index(after i: Int) -> Int
    {
      return i + 1
    }
    
    subscript(position: Int) -> TreeEntry
    {
      guard let result = git_tree_entry_byindex(tree.tree, position),
            let owner = git_tree_owner(tree.tree)
      else {
        return NullEntry()
      }
      
      return GitTreeEntry(entry: result, owner: owner)
    }
  }
  
  var entries: EntryCollection
  { EntryCollection(tree: self) }
  
  let tree: OpaquePointer
  
  var oid: OID
  {
    guard let result = git_tree_id(tree)
    else { return GitOID.zero() }
    
    return GitOID(oidPtr: result)
  }
  
  var count: Int
  { git_tree_entrycount(tree) }
  
  init(tree: OpaquePointer)
  {
    self.tree = tree
  }
  
  init?(oid: git_oid, repo: OpaquePointer)
  {
    var tree: OpaquePointer? = nil
    var oid = oid
    let result = git_object_lookup(&tree, repo, &oid, GIT_OBJECT_TREE)
    guard result == 0,
          let finalTree = tree
    else { return nil }
    
    self.tree = finalTree
  }
  
  deinit
  {
    git_tree_free(tree)
  }
  
  func entry(named name: String) -> TreeEntry?
  {
    guard let result = git_tree_entry_byname(tree, name),
          let owner = git_tree_owner(tree)
    else { return nil }
    
    return GitTreeEntry(entry: result, owner: owner)
  }
  
  func entry(path: String) -> TreeEntry?
  {
    guard let owner = git_tree_owner(tree)
    else { return nil }
    var entry: OpaquePointer?
    let result = git_tree_entry_bypath(&entry, tree, path)
    guard result == 0,
          let finalEntry = entry
    else { return nil }
    
    return GitTreeEntry(entry: finalEntry, owner: owner)
  }
  
  func entry(at index: Int) -> TreeEntry?
  {
    switch index {
      case 0..<count:
        return entries[index]
      default:
        return nil
    }
  }
  
  func walkEntries(callback: (TreeEntry, String) -> Void)
  {
    walkEntries(root: "", callback: callback)
  }
  
  private func walkEntries(root: String, callback: (TreeEntry, String) -> Void)
  {
    for entry in entries {
      callback(entry, root)
      if let tree = entry.object as? GitTree {
        tree.walkEntries(root: root.appending(pathComponent: entry.name),
                         callback: callback)
      }
    }
  }
}

class GitTreeEntry: TreeEntry
{
  let entry: OpaquePointer
  let owner: OpaquePointer
  
  var oid: OID
  {
    guard let gitOID = git_tree_entry_id(entry)
    else { return GitOID.zero() }
    
    return GitOID(oidPtr: gitOID)
  }
  
  var type: GitObjectType
  {
    let result = git_tree_entry_type(entry)
    
    return GitObjectType(rawValue: result.rawValue) ?? .invalid
  }
  
  var name: String
  {
    let name = git_tree_entry_name(entry)
    
    return name.map { String(cString: $0) } ?? ""
  }
  
  var object: OIDObject?
  {
    var gitObject: OpaquePointer?
    let result = git_tree_entry_to_object(&gitObject, owner, entry)
    guard result == 0,
          let finalObject = gitObject
    else { return nil }
    
    switch type {
      case .blob:
        return GitBlob(blob: finalObject)
      case .tree:
        return GitTree(tree: finalObject)
      default:
        return nil
    }
  }
  
  init(entry: OpaquePointer, owner: OpaquePointer)
  {
    self.entry = entry
    self.owner = owner
  }
}
