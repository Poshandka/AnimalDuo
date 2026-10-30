// Exercise the actual save editor with synthetic saves; no Nintendo data needed.
import Foundation
import zlib
@main struct ResidentCheck {
 static func main() throws {
  var failed=0, passed=0
  func check(_ value: Bool,_ label:String) { if value {passed+=1} else {failed+=1;print("FAIL",label)} }
  func rejects(_ kind:ResidentError,_ label:String,_ fn:() throws -> Void) {do {try fn();check(false,label)} catch {check(error as? ResidentError == kind,label)}}
  let fm=FileManager.default, base=URL(fileURLWithPath:CommandLine.arguments[1])
  try fm.createDirectory(at:base,withIntermediateDirectories:true)
  let animals=(0..<417).map {i in ResidentAnimal(id:String(format:"ant%03d",i),name:"Animal \(i)",english:"Animal \(i)",phrase:"hello",species:i/100,variant:i%100,personality:i%8)}
  // The first few identities use real save ID syntax. Extra catalog rows only
  // exercise catalog sizing/validation without importing game assets.
  let real=(0..<417).map { i -> ResidentAnimal in
   let prefixes=["ant","bea","brd","bul","cat"]
   var animal = ResidentAnimal(id:String(format:"%@%02d",prefixes[i/100],i%100),name:animals[i].name,english:animals[i].english,phrase:"hello",species:i/100,variant:i%100,personality:i%8)
   var data = Data(repeating: 0, count: ResidentSave.npcSize+ResidentSave.houseSize)
   data[0] = UInt8(animal.species); data[1] = UInt8(animal.variant); data[2] = UInt8(animal.personality)
   data[0x12678] = 3; data[0x12679] = 2
   for player in 0..<8 {
    let m = 4+player*0x5f0
    data[m+0x18] = 2 // Unassigned GSavePlayerId metadata, overwritten locally.
    data[m+0x574] = 0xfe; data[m+0x575] = 0xff
    data[m+0x5bc] = 0xff; data[m+0x5bd] = 0xff
   }
   // Donor acquaintance records must never become a new local friendship.
   data[4+0x38+10] = 200; data[4+0x38+13] = 1; data[4+0x14c] = 65
   data[ResidentSave.npcSize] = 2; data[ResidentSave.npcSize+4] = 2
   data[ResidentSave.npcSize+0x1c5] = 255
   var length = compressBound(uLong(data.count)), compressed = Data(count: Int(compressBound(uLong(data.count))))
   let status = data.withUnsafeBytes { src in compressed.withUnsafeMutableBytes { dst in
    compress2(dst.bindMemory(to: UInt8.self).baseAddress, &length, src.bindMemory(to: UInt8.self).baseAddress, uLong(src.count), 6)
   } }
   precondition(status == Z_OK); animal.template = compressed.prefix(Int(length)).base64EncodedString()
   return animal
  }
  let catalog=ResidentCatalog(schema:"nxnative-acnh-residents/2",version:"3.0.3",animals:real)
  let catURL=base.appendingPathComponent("catalog.json");try JSONEncoder().encode(catalog).write(to:catURL)
  _ = try ResidentCatalog.load(catURL)
  let saveURL=base.appendingPathComponent("save");try fm.createDirectory(at:saveURL,withIntermediateDirectories:true)
  var header=Data(repeating:0,count:0x300)
  func put(_ data:inout Data,_ n:UInt32,_ at:Int) { for j in 0..<4 {data[at+j]=UInt8(truncatingIfNeeded:n>>(j*8))} }
  put(&header,0xa0002,0);put(&header,0xa0028,4);header[8]=2;header[12]=2;header[14]=34
  for i in 0..<128 {put(&header,UInt32(i),0x100+i*4)}
  var plain=Data(repeating:0,count:ResidentSave.fileSize);plain.replaceSubrange(0..<0x100,with:header.prefix(0x100))
  for i in 0..<10 {
   let a=ResidentSave.npcBase+i*ResidentSave.npcSize;plain[a]=i<3 ? 0:35;plain[a+1]=i<3 ? UInt8(i):0;plain[a+2]=i<3 ? UInt8(i):8;plain[a+0x12678]=i<3 ? 0:5
   let h=ResidentSave.houseBase+i*ResidentSave.houseSize;plain[h+0x1c4]=i<3 ? UInt8(i):255;plain[h+0x1c5]=255;put(&plain,2,h);put(&plain,i<3 ? 2:0,h+4)
   plain[ResidentSave.buildingBase+i*20]=UInt8(i+9)
  }
  // Two distinct local player identities and established relationships.
  for npc in 0..<3 {
   for player in 0..<8 { plain[ResidentSave.npcBase+npc*ResidentSave.npcSize+4+player*0x5f0+0x18] = 2 }
   for player in 0..<2 {
    let m=ResidentSave.npcBase+npc*ResidentSave.npcSize+4+player*0x5f0
    put(&plain,UInt32(100+player),m);put(&plain,UInt32(200+player),m+0x1c)
    plain[m+0x42]=UInt8(90+player);plain[m+0x38+13]=1
    plain[m+0x14c]=UInt8(65+player)
   }
  }
  for (at,n) in ResidentSave.hashes {put(&plain,ResidentCipher.murmur(plain,at+4,n),at)}
  let cipher=try ResidentCipher.transform(plain,header:header)
  check(try ResidentCipher.transform(cipher,header:header)==plain,"encryption roundtrip")
  check(ResidentCipher.murmur(Data([0,1,2,3]),0,4)==0xf4c0ec39,"standard Murmur3 known answer")
  try header.write(to:saveURL.appendingPathComponent("mainHeader.dat"));try cipher.write(to:saveURL.appendingPathComponent("main.dat"))
  try Data("other player progress".utf8).write(to:saveURL.appendingPathComponent("personal-fixture.dat"))
  let doc=try ResidentSave(folder:saveURL,catalog:catalog)
  check(doc.count==3 && doc.vacantPlots.count==7,"roster and plot association")
  // Dialogue resources supply missing starter text. Save origins must remain
  // intact because the same identity controls NPC tent-to-house construction.
  for personality in 0..<8 {
   let test=try ResidentSave(folder:saveURL,catalog:catalog)
   let target=real[8+personality]
   try test.replace(slot:0,with:target)
   let a=ResidentSave.npcBase, end=a+ResidentSave.npcSize
   check(test.plain[a+0x12678] == 0,"starter construction origin preserved for personality \(personality)")
   check(test.plain.subdata(in:a+4..<a+4+8*0x5f0)==plain.subdata(in:a+4..<a+4+8*0x5f0),"all player memories preserved for personality \(personality)")
   check(test.plain.subdata(in:end..<plain.count)==plain.subdata(in:end..<plain.count),"houses, other residents and player progress preserved for personality \(personality)")
   check(test.plain[a+0x12679]==plain[a+0x12679] && test.plain[a+0x1267a]==0,"recruitment and movement retained for personality \(personality)")
  }
  rejects(.duplicate,"duplicate animal"){try doc.replace(slot:1,with:real[0])}
  rejects(.invalid,"negative slot"){try doc.replace(slot:-1,with:real[4])}
  rejects(.plot,"occupied plot"){try doc.add(real[4],plot:0)}
  try doc.replace(slot:0,with:real[4]);let backup=try doc.save()
  let edited=try ResidentSave(folder:saveURL,catalog:catalog)
  check(edited.slots[0].animal?.id==real[4].id,"replacement persisted")
  check(try Data(contentsOf:saveURL.appendingPathComponent("mainHeader.dat"))==header,"encryption header retained")
  check(try Data(contentsOf:backup.appendingPathComponent("main.dat"))==cipher,"backup is original encrypted save")
  rejects(.changed,"stale writer rejected"){try doc.save()}
  try edited.add(real[5],plot:3);try edited.save()
  let added=try ResidentSave(folder:saveURL,catalog:catalog)
  check(added.count==4 && added.slots[3].animal?.id==real[5].id && added.slots[3].plot==3,"add updates resident and house")
  let newBase=ResidentSave.npcBase+3*ResidentSave.npcSize
  for player in 0..<8 {
   let m=newBase+4+player*0x5f0,old=ResidentSave.npcBase+4+player*0x5f0
   check(added.plain.subdata(in:m..<m+0x38)==plain.subdata(in:old..<old+0x38),"new resident local identity \(player)")
   check(added.plain[m+0x42] == (player<2 ? 25:0),"new resident friendship default \(player)")
   check(added.plain[m+0x38+13]==0 && added.plain[m+0x14c]==0,"no donor acquaintance or greeting \(player)")
   check(added.plain[m+0x574]==0xfe && added.plain[m+0x575]==0xff && added.plain[m+0x5bc]==0xff,"new memory invalid-date sentinels retained \(player)")
  }
  try added.remove(slot:3);try added.save()
  let removed=try ResidentSave(folder:saveURL,catalog:catalog)
  check(removed.count==3 && removed.vacantPlots.contains(3),"delete releases the same plot")
  try removed.remove(slot:2);try removed.save()
  let minimum=try ResidentSave(folder:saveURL,catalog:catalog)
  rejects(.minimum,"two starting residents protected"){try minimum.remove(slot:1)}
  guard let oldest=minimum.backups.first(where: { $0.url.resolvingSymlinksInPath().path==backup.resolvingSymlinksInPath().path }) else {fatalError("backup missing from listing: \(backup.path) in \(minimum.backups.map { $0.url.path })")}
  try minimum.restore(oldest)
  check(try Data(contentsOf:saveURL.appendingPathComponent("main.dat"))==cipher,"atomic whole-save restore")
  check(String(data:try Data(contentsOf:saveURL.appendingPathComponent("personal-fixture.dat")),encoding:.utf8)=="other player progress","restore retains other save files")
  let restored=try ResidentSave(folder:saveURL,catalog:catalog)
  try Data("tamper".utf8).write(to:backup.appendingPathComponent("personal-fixture.dat"))
  rejects(.backup,"tampered backup refused"){try restored.restore(oldest)}
  let full=try ResidentSave(folder:saveURL,catalog:catalog)
  for i in 3..<10 {try full.add(real[10+i],plot:i)}
  check(full.count==10,"all ten slots usable")
  rejects(.full,"eleventh resident refused"){try full.add(real[30],plot:3)}
  try full.remove(slot:9);try full.add(real[40],plot:9)
  check(full.count==10 && full.slots[9].animal?.id==real[40].id,"full roster delete and add")
  var damaged=cipher;damaged[0x120]^=1;try damaged.write(to:saveURL.appendingPathComponent("main.dat"))
  rejects(.damaged,"cipher corruption refused"){_ = try ResidentSave(folder:saveURL,catalog:catalog)}
  try cipher.write(to:saveURL.appendingPathComponent("main.dat"));var oldHeader=header;oldHeader[14]=33;try oldHeader.write(to:saveURL.appendingPathComponent("mainHeader.dat"))
  rejects(.version,"different save revision refused"){_ = try ResidentSave(folder:saveURL,catalog:catalog)}
  try header.write(to:saveURL.appendingPathComponent("mainHeader.dat"));let link=saveURL.appendingPathComponent("link");try fm.createSymbolicLink(at:link,withDestinationURL:catURL)
  rejects(.path,"symlinks refused"){_ = try ResidentSave(folder:saveURL,catalog:catalog)}
  try fm.removeItem(at:link);try Data().write(to:saveURL.appendingPathComponent("write.pending"))
  rejects(.path,"unfinished writes refused"){_ = try ResidentSave(folder:saveURL,catalog:catalog)}
  print("resident save:",passed,"passed,",failed,"failed");exit(failed==0 ? 0:1)
 }
}
