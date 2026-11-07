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
   let phrase = i == 8 ? String(repeating:"x",count:19)+"\u{1F332}" : "new-\(i)"
   var animal = ResidentAnimal(id:String(format:"%@%02d",prefixes[i/100],i%100),name:animals[i].name,english:animals[i].english,phrase:phrase,species:i/100,variant:i%100,personality:i%8)
   animal.phrases = (0..<11).map { $0 == 9 ? phrase : "L\($0)-\(i)" }
   var data = Data(repeating: 0, count: ResidentSave.npcSize+ResidentSave.houseSize)
   data[0] = UInt8(animal.species); data[1] = UInt8(animal.variant); data[2] = UInt8(animal.personality)
   data[0x12678] = 3; data[0x12679] = 2
   data[0x1267a] = (i == 5 || i == 45) ? 1 : 0 // Two real templates retain a pending move.
   data[0x12674] = 0xe4; data[0x12675] = 7; data[0x12676] = 4; data[0x12677] = 22 // Donor: 2020-04-22.
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
  for (label, value) in [("too many UTF-16 units",String(repeating:"x",count:22)),("empty translation",""),("embedded terminator","x\0y")] {
   var bad = real; bad[0].phrases?[0] = value
   try JSONEncoder().encode(ResidentCatalog(schema:catalog.schema,version:catalog.version,animals:bad)).write(to:catURL)
   rejects(.catalog,label){_ = try ResidentCatalog.load(catURL)}
  }
  var bad = real; bad[0].phrases?.removeLast()
  try JSONEncoder().encode(ResidentCatalog(schema:catalog.schema,version:catalog.version,animals:bad)).write(to:catURL)
  rejects(.catalog,"incomplete language array"){_ = try ResidentCatalog.load(catURL)}
  bad = real; bad[0].phrases?[9] = "different default"
  try JSONEncoder().encode(ResidentCatalog(schema:catalog.schema,version:catalog.version,animals:bad)).write(to:catURL)
  rejects(.catalog,"Chinese default disagrees with translation"){_ = try ResidentCatalog.load(catURL)}
  try JSONEncoder().encode(catalog).write(to:catURL)
  let saveURL=base.appendingPathComponent("save");try fm.createDirectory(at:saveURL,withIntermediateDirectories:true)
  var header=Data(repeating:0,count:0x300)
  func put(_ data:inout Data,_ n:UInt32,_ at:Int) { for j in 0..<4 {data[at+j]=UInt8(truncatingIfNeeded:n>>(j*8))} }
  func putText(_ data:inout Data,_ text:String,_ at:Int) {
   for (i,c) in text.utf16.enumerated() {data[at+2*i]=UInt8(truncatingIfNeeded:c);data[at+2*i+1]=UInt8(c>>8)}
  }
  func addressingOffsets(_ npc:Int)->Set<Int> {
   var result=Set<Int>()
   for p in 0..<8 {
    let m=npc+4+p*0x5f0;result.formUnion(m+0x138..<m+0x570)
    for f in [3,19,21,31] {result.insert(m+0x38+f)}
   }
   for p in 0..<160 {
    let m=npc+0x2f84+p*0x158
    for f in [3,19,21,31] {result.insert(m+0x38+f)}
   }
   return result
  }
  func phraseHistoryOffsets(_ npc:Int)->Set<Int> {
   Set((0..<8).map{npc+4+$0*0x5f0+0x38+20}).union((0..<160).map{npc+0x2f84+$0*0x158+0x38+20})
  }
  put(&header,0xa0002,0);put(&header,0xa0028,4);header[8]=2;header[12]=2;header[14]=34
  for i in 0..<128 {put(&header,UInt32(i),0x100+i*4)}
  var plain=Data(repeating:0,count:ResidentSave.fileSize);plain.replaceSubrange(0..<0x100,with:header.prefix(0x100))
  plain[0x97d670]=0xea;plain[0x97d671]=7;plain[0x97d672]=11;plain[0x97d673]=7 // Island: 2026-11-07.
  for i in 0..<10 {
   let a=ResidentSave.npcBase+i*ResidentSave.npcSize;plain[a]=i<3 ? 0:35;plain[a+1]=i<3 ? UInt8(i):0;plain[a+2]=i<3 ? UInt8(i):8;plain[a+0x12678]=i<3 ? 0:5
   let h=ResidentSave.houseBase+i*ResidentSave.houseSize;plain[h+0x1c4]=i<3 ? UInt8(i):255;plain[h+0x1c5]=255;put(&plain,2,h);put(&plain,i<3 ? 2:0,h+4)
   plain[ResidentSave.buildingBase+i*20]=UInt8(i+9)
  }
  // Two distinct local player identities and established relationships.
  for npc in 0..<3 {
   let a=ResidentSave.npcBase+npc*ResidentSave.npcSize
   // Independent S00 fixture: 11 char16[22] strings at NPC+0x10768,
   // with the active Chinese phrase at +0x108f4, not NHSE's +0x10794.
   for language in 0..<11 {
    let old=Array(String(repeating:"q",count:21).utf16)+[0]
    for (i,c) in old.enumerated(){plain[a+0x10768+language*44+i*2]=UInt8(c)}
   }
   for flag in [8,10] {plain[a+0x1267c+flag*2]=1;plain[a+0x1267c+flag*2+1]=1}
   plain[a+0x1267c+9*2]=0x23;plain[a+0x1267c+9*2+1]=1
   for player in 0..<8 {
    let m=a+4+player*0x5f0;plain[m+0x18]=2
    putText(&plain,"OLD-\(player)",m+0x138)
    for language in 0..<11 {putText(&plain,"OLD-\(player)-\(language)",m+0x14c+language*0x60)}
    plain[m+0x56c]=0xea;plain[m+0x56d]=7;plain[m+0x56e]=11;plain[m+0x56f]=5
    for flag in [3,19,20,21,31] {plain[m+0x38+flag]=1}
   }
   for visitor in 0..<160 {
    let m=a+0x2f84+visitor*0x158
    put(&plain,UInt32(500+visitor),m);put(&plain,UInt32(800+visitor),m+0x1c)
    plain[m+0x38+10]=55;plain[m+0x38+13]=1;plain[m+0x138]=0xea;plain[m+0x139]=7
    for flag in [3,19,20,21,31] {plain[m+0x38+flag]=1}
   }
   for player in 0..<2 {
    let m=ResidentSave.npcBase+npc*ResidentSave.npcSize+4+player*0x5f0
    put(&plain,UInt32(100+player),m);put(&plain,UInt32(200+player),m+0x1c)
    plain[m+0x42]=UInt8(90+player);plain[m+0x38+13]=1
   }
  }
  for (at,n) in ResidentSave.hashes {put(&plain,ResidentCipher.murmur(plain,at+4,n),at)}
  let cipher=try ResidentCipher.transform(plain,header:header)
  check(try ResidentCipher.transform(cipher,header:header)==plain,"encryption roundtrip")
  check(ResidentCipher.murmur(Data([0,1,2,3]),0,4)==0xf4c0ec39,"standard Murmur3 known answer")
  try header.write(to:saveURL.appendingPathComponent("mainHeader.dat"));try cipher.write(to:saveURL.appendingPathComponent("main.dat"))
  try Data("other player progress".utf8).write(to:saveURL.appendingPathComponent("personal-fixture.dat"))
  if CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "--prepare-only" {
   print("Synthetic resident fixture prepared"); return
  }
  let doc=try ResidentSave(folder:saveURL,catalog:catalog)
  func phrase(_ data:Data,_ npc:Int,_ language:Int)->String {
   let at=0x120+npc*0x13230+0x10768+language*44
   let words=(0..<22).map { UInt16(data[at+$0*2]) | UInt16(data[at+$0*2+1])<<8 }
   return String(decoding:words.prefix(while:{$0 != 0}),as:UTF16.self)
  }
  check(doc.count==3 && doc.vacantPlots.count==7,"roster and plot association")
  // Dialogue resources supply missing starter text. Save origins must remain
  // intact because the same identity controls NPC tent-to-house construction.
  for personality in 0..<8 {
   let test=try ResidentSave(folder:saveURL,catalog:catalog)
   let target=real[8+personality]
   try test.replace(slot:0,with:target)
   let a=ResidentSave.npcBase, end=a+ResidentSave.npcSize
   check(test.plain[a+0x12678] == 0,"starter construction origin preserved for personality \(personality)")
   let speech=addressingOffsets(a).union(phraseHistoryOffsets(a))
   check((a+4..<a+4+8*0x5f0).allSatisfy {test.plain[$0]==plain[$0] || speech.contains($0)},"relationships preserved outside speech for personality \(personality)")
   check(speech.allSatisfy{test.plain[$0]==0},"all eight players lose old custom speech for personality \(personality)")
   check(test.plain.subdata(in:end..<plain.count)==plain.subdata(in:end..<plain.count),"houses, other residents and player progress preserved for personality \(personality)")
   check(test.plain[a+0x12679]==plain[a+0x12679] && test.plain[a+0x1267a]==0,"recruitment and movement retained for personality \(personality)")
   for language in 0..<11 {
    check(phrase(test.plain,0,language)==target.phrases![language],"localized replacement phrase \(personality)/\(language)")
    let bytes=Array(target.phrases![language].utf16).count*2,at=a+0x10768+language*44
    check(test.plain[at+bytes..<at+44].allSatisfy{$0==0},"old phrase suffix cleared \(personality)/\(language)")
   }
   check(test.slots[0].phrase==target.phrase,"manager reads Chinese phrase \(personality)")
   check([8,10].allSatisfy {test.plain[a+0x1267c+$0*2]==0 && test.plain[a+0x1267c+$0*2+1]==0},"full phrase flag words cleared \(personality)")
   var allowed=Set(a..<a+3);allowed.formUnion(a+0x10768..<a+0x1094c)
   allowed.formUnion(speech)
   for flag in [8,10] {allowed.insert(a+0x1267c+flag*2);allowed.insert(a+0x1267c+flag*2+1)}
   check(plain.indices.allSatisfy {test.plain[$0]==plain[$0] || allowed.contains($0)},"only identity and phrase state changed \(personality)")
  }
  var legacy = real;legacy[8].phrases=nil
  let legacyDoc=try ResidentSave(folder:saveURL,catalog:ResidentCatalog(schema:catalog.schema,version:catalog.version,animals:legacy))
  try legacyDoc.replace(slot:0,with:legacy[8])
  check(phrase(legacyDoc.plain,0,9)==legacy[8].phrase,"legacy catalog writes Chinese instead of English")
  check((0..<11).filter{$0 != 9}.allSatisfy{phrase(legacyDoc.plain,0,$0).isEmpty},"legacy catalog cannot carry old animal translations")
  let resetURL=base.appendingPathComponent("reset");try fm.createDirectory(at:resetURL,withIntermediateDirectories:true)
  try header.write(to:resetURL.appendingPathComponent("mainHeader.dat"));try cipher.write(to:resetURL.appendingPathComponent("main.dat"))
  let reset=try ResidentSave(folder:resetURL,catalog:catalog)
  rejects(.invalid,"negative phrase-reset slot"){try reset.restoreDefaultPhrase(slot:-1)}
  rejects(.invalid,"empty phrase-reset slot"){try reset.restoreDefaultPhrase(slot:9)}
  try reset.restoreDefaultPhrase(slot:0)
  let resetBackup=try reset.save(),reloaded=try ResidentSave(folder:resetURL,catalog:catalog)
  check(reloaded.slots[0].animal==real[0] && reloaded.slots[0].phrase==real[0].phrase,"reset persists default without changing identity")
  var allowedReset=Set(0x120+0x10768..<0x120+0x1094c);allowedReset.formUnion([0x110,0x111,0x112,0x113])
  allowedReset.formUnion(phraseHistoryOffsets(0x120))
  for flag in [8,10] {allowedReset.insert(0x120+0x1267c+flag*2);allowedReset.insert(0x120+0x1267c+flag*2+1)}
  check(plain.indices.allSatisfy {reloaded.plain[$0]==plain[$0] || allowedReset.contains($0)},"phrase reset preserves all unrelated save bytes")
  check(try Data(contentsOf:resetBackup.appendingPathComponent("main.dat"))==cipher,"phrase reset backs up original save")
  check(phraseHistoryOffsets(0x120).allSatisfy{reloaded.plain[$0]==0},"phrase reset clears obsolete player authorship")
  check(addressingOffsets(0x120).allSatisfy{reloaded.plain[$0]==plain[$0]},"phrase-only reset preserves custom nicknames and greetings")
  let addressURL=base.appendingPathComponent("addressing");try fm.createDirectory(at:addressURL,withIntermediateDirectories:true)
  try header.write(to:addressURL.appendingPathComponent("mainHeader.dat"));try cipher.write(to:addressURL.appendingPathComponent("main.dat"))
  let address=try ResidentSave(folder:addressURL,catalog:catalog)
  rejects(.invalid,"empty addressing-reset slot"){try address.restoreDefaultAddressing(slot:9)}
  try address.restoreDefaultAddressing(slot:0);let addressBackup=try address.save()
  let addressReload=try ResidentSave(folder:addressURL,catalog:catalog)
  var allowedAddress=addressingOffsets(0x120);allowedAddress.formUnion([0x110,0x111,0x112,0x113])
  check(addressingOffsets(0x120).allSatisfy{addressReload.plain[$0]==0},"addressing reset persists for all eight players and eleven languages")
  check(plain.indices.allSatisfy{addressReload.plain[$0]==plain[$0] || allowedAddress.contains($0)},"addressing reset preserves identities, phrases, gifts, progress and friendship")
  check(try Data(contentsOf:addressBackup.appendingPathComponent("main.dat"))==cipher,"addressing reset backs up original save")
  rejects(.duplicate,"same animal cannot erase custom speech"){try doc.replace(slot:0,with:real[0])}
  check(doc.plain==plain,"same-animal rejection leaves every byte unchanged")
  let matrixURL=base.appendingPathComponent("matrix");try fm.createDirectory(at:matrixURL,withIntermediateDirectories:true)
  try header.write(to:matrixURL.appendingPathComponent("mainHeader.dat"))
  func writeFixture(_ source:Data) throws {
   var output=source
   for(at,n)in ResidentSave.hashes {put(&output,ResidentCipher.murmur(output,at+4,n),at)}
   try ResidentCipher.transform(output,header:header).write(to:matrixURL.appendingPathComponent("main.dat"))
  }
  let baseNPC=0x120
  var matrixAllowed=addressingOffsets(baseNPC).union(phraseHistoryOffsets(baseNPC))
  matrixAllowed.formUnion(baseNPC..<baseNPC+3);matrixAllowed.formUnion(baseNPC+0x10768..<baseNPC+0x1094c)
  for flag in [8,10] {matrixAllowed.insert(baseNPC+0x1267c+flag*2);matrixAllowed.insert(baseNPC+0x1267c+flag*2+1)}
  for oldPersonality in 0..<8 {
   var source=plain;source[baseNPC+1]=UInt8(32+oldPersonality);source[baseNPC+2]=UInt8(oldPersonality)
   try writeFixture(source)
   let originalMatrix=try ResidentSave(folder:matrixURL,catalog:catalog)
   for personality in 0..<8 {
    let matrix=try ResidentSave(folder:matrixURL,catalog:catalog),target=real[8+personality]
    try matrix.replace(slot:0,with:target)
    check(matrix.slots[0].animal==target && matrix.plain[baseNPC+2]==target.personality,"identity and gender matrix \(oldPersonality)/\(personality)")
    check(addressingOffsets(baseNPC).union(phraseHistoryOffsets(baseNPC)).allSatisfy{matrix.plain[$0]==0},"speech reset matrix \(oldPersonality)/\(personality)")
    check(matrix.plain.indices.allSatisfy{matrix.plain[$0]==originalMatrix.plain[$0] || matrixAllowed.contains($0)},"unrelated save bytes retained matrix \(oldPersonality)/\(personality)")
   }
  }
  for pending in ["move type","forced departure","pending house occupant","pending house elsewhere"] {
   var source=plain
   if pending=="move type" {source[baseNPC+0x1267a]=1}
   if pending=="forced departure" {source[baseNPC+0x1267c+24*2]=1}
   if pending=="pending house occupant" {source[ResidentSave.houseBase+0x1c5]=1}
   if pending=="pending house elsewhere" {source[ResidentSave.houseBase+9*ResidentSave.houseSize+0x1c5]=0}
   try writeFixture(source)
   let pendingDoc=try ResidentSave(folder:matrixURL,catalog:catalog),snapshot=pendingDoc.plain
   check(pendingDoc.slots[0].moving,"pending edit state detected: \(pending)")
   rejects(.moving,"replacement blocked: \(pending)"){try pendingDoc.replace(slot:0,with:real[8])}
   rejects(.moving,"phrase reset blocked: \(pending)"){try pendingDoc.restoreDefaultPhrase(slot:0)}
   rejects(.moving,"addressing reset blocked: \(pending)"){try pendingDoc.restoreDefaultAddressing(slot:0)}
   rejects(.moving,"delete blocked: \(pending)"){try pendingDoc.remove(slot:0)}
   check(pendingDoc.plain==snapshot,"pending rejection retains every byte: \(pending)")
  }
  for resident in 0..<3 {
   for plot in 0..<10 where plot != resident {
    var source=plain;source[ResidentSave.houseBase+plot*ResidentSave.houseSize+0x1c5]=UInt8(resident)
    try writeFixture(source)
    let pending=try ResidentSave(folder:matrixURL,catalog:catalog),before=pending.plain
    check(pending.slots[resident].moving,"pending reference across houses \(resident)/\(plot)")
    rejects(.moving,"pending reference prevents delete \(resident)/\(plot)"){try pending.remove(slot:resident)}
    rejects(.moving,"pending reference prevents replacement \(resident)/\(plot)"){try pending.replace(slot:resident,with:real[8])}
    check(pending.plain==before,"pending cross-house reference is retained")
   }
  }
  for field in [0x1c4,0x1c5] {
   var source=plain;source[ResidentSave.houseBase+4*ResidentSave.houseSize+field]=3
   let reserved=0x120+3*0x13230;source[reserved+0x10768]=0x5a
   try writeFixture(source)
   let reservation=try ResidentSave(folder:matrixURL,catalog:catalog),before=reservation.plain
   try reservation.add(real[8],plot:3)
   check(reservation.slots[3].animal==nil && reservation.slots[4].animal==real[8] && reservation.slots[4].plot==3,"addition skips reserved empty NPC in house field \(field)")
   check(reservation.plain[reserved..<reserved+0x13230]==before[reserved..<reserved+0x13230],"reserved record remains byte-identical")
   let deletion=try ResidentSave(folder:matrixURL,catalog:catalog)
   try deletion.remove(slot:2)
   check(deletion.plain[0x120+2*0x13230+0x10768]==0,"reserved NPC is not used as an empty template")
  }
  var reservedSource=plain
  for slot in 3..<10 {reservedSource[ResidentSave.houseBase+(slot-3)*ResidentSave.houseSize+0x1c5]=UInt8(slot)}
  try writeFixture(reservedSource)
  let reservations=try ResidentSave(folder:matrixURL,catalog:catalog),reservedBefore=reservations.plain
  check(reservations.vacantPlots.contains(9),"free plot can coexist with reserved NPC slots")
  rejects(.moving,"all remaining NPC slots reserved"){try reservations.add(real[8],plot:9)}
  check(reservations.plain==reservedBefore,"exhausted reservation leaves every byte unchanged")
  var permuted=plain
  for plot in 0..<10 {
   let npc=0x120+plot*0x13230
   if plot>=3 {permuted[npc]=0;permuted[npc+1]=UInt8(10+plot);permuted[npc+2]=UInt8((10+plot)%8);permuted[npc+0x12678]=3}
   permuted[ResidentSave.houseBase+plot*ResidentSave.houseSize+0x1c4]=UInt8((plot+3)%10)
   put(&permuted,2,ResidentSave.houseBase+plot*ResidentSave.houseSize+4)
  }
  try writeFixture(permuted)
  let shifted=try ResidentSave(folder:matrixURL,catalog:catalog),shiftedBefore=shifted.plain
  check(shifted.slots.allSatisfy{$0.plot==($0.id+7)%10},"NPC and plot indexes are independent")
  try shifted.remove(slot:4);try shifted.add(real[40],plot:1)
  check(shifted.count==10 && shifted.slots[4].animal==real[40] && shifted.slots[4].plot==1,"permuted full-roster delete and addition retain mapping")
  let changedNPC=0x120+4*0x13230..<0x120+5*0x13230,changedHouse=ResidentSave.houseBase+ResidentSave.houseSize..<ResidentSave.houseBase+2*ResidentSave.houseSize
  check(shifted.plain.indices.allSatisfy{shifted.plain[$0]==shiftedBefore[$0] || changedNPC.contains($0) || changedHouse.contains($0)},"permuted lifecycle preserves all unrelated bytes")
  // New arrivals use the saved island calendar, including time travel. Neither
  // the template's 2020 date nor the host's clock defines this checkpoint.
  for (year,month,day) in [(2024,2,29),(2010,1,2),(2050,12,31)] {
   var source=plain
   source[0x97d670]=UInt8(truncatingIfNeeded:year);source[0x97d671]=UInt8(year>>8)
   source[0x97d672]=UInt8(month);source[0x97d673]=UInt8(day)
   try writeFixture(source)
   let arrival=try ResidentSave(folder:matrixURL,catalog:catalog)
   try arrival.add(real[5],plot:3)
   let at=0x120+3*0x13230+0x12674
   check(arrival.plain[at..<at+4]==source[0x97d670..<0x97d674],"new arrival uses island date \(year)-\(month)-\(day)")
  }
  for (year,month,day) in [(0,0,0),(2026,2,29),(2026,13,1),(2026,4,31)] {
   var source=plain
   source[0x97d670]=UInt8(truncatingIfNeeded:year);source[0x97d671]=UInt8(year>>8)
   source[0x97d672]=UInt8(month);source[0x97d673]=UInt8(day)
   try writeFixture(source)
   let arrival=try ResidentSave(folder:matrixURL,catalog:catalog),before=arrival.plain
   rejects(.damaged,"invalid island date refuses addition \(year)-\(month)-\(day)"){try arrival.add(real[5],plot:3)}
   check(arrival.plain==before,"invalid date leaves every save byte intact")
  }
  rejects(.duplicate,"duplicate animal"){try doc.replace(slot:1,with:real[0])}
  rejects(.invalid,"negative slot"){try doc.replace(slot:-1,with:real[4])}
  rejects(.plot,"occupied plot"){try doc.add(real[4],plot:0)}
  try doc.replace(slot:0,with:real[4]);let backup=try doc.save()
  let edited=try ResidentSave(folder:saveURL,catalog:catalog)
  check(edited.slots[0].animal?.id==real[4].id,"replacement persisted")
  check((0..<11).allSatisfy{phrase(edited.plain,0,$0)==real[4].phrases![$0]},"all replacement translations persist after encrypted reload")
  check(try Data(contentsOf:saveURL.appendingPathComponent("mainHeader.dat"))==header,"encryption header retained")
  check(try Data(contentsOf:backup.appendingPathComponent("main.dat"))==cipher,"backup is original encrypted save")
  rejects(.changed,"stale writer rejected"){try doc.save()}
  try edited.add(real[5],plot:3);try edited.save()
  let added=try ResidentSave(folder:saveURL,catalog:catalog)
  check(added.count==4 && added.slots[3].animal?.id==real[5].id && added.slots[3].plot==3,"add updates resident and house")
  check(!added.slots[3].moving,"new occupied house does not inherit donor pending move")
  check((0..<11).allSatisfy{phrase(added.plain,3,$0)==real[5].phrases![$0]},"addition uses new animal defaults in every language")
  let newBase=ResidentSave.npcBase+3*ResidentSave.npcSize
  check(added.plain[newBase+0x12674..<newBase+0x12678]==plain[0x97d670..<0x97d674],"arrival date survives encrypted reload")
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
  for change in ["modified","added","deleted"] {
   let root=base.appendingPathComponent("stale-\(change)"),url=root.appendingPathComponent("save"),player=url.appendingPathComponent("Villager1/personal.dat")
   try fm.createDirectory(at:player.deletingLastPathComponent(),withIntermediateDirectories:true)
   try header.write(to:url.appendingPathComponent("mainHeader.dat"));try cipher.write(to:url.appendingPathComponent("main.dat"))
   try Data("first progress".utf8).write(to:player)
   let baseline=try ResidentSave(folder:url,catalog:catalog),copy=try baseline.save()
   let stale=try ResidentSave(folder:url,catalog:catalog)
   try stale.replace(slot:0,with:real[8])
   let savedMain=try Data(contentsOf:url.appendingPathComponent("main.dat"))
   if change=="modified" {try Data("later progress".utf8).write(to:player)}
   if change=="added" {try Data("new player progress".utf8).write(to:url.appendingPathComponent("Villager1/new.dat"))}
   if change=="deleted" {try fm.removeItem(at:player)}
   let backupsBefore=stale.backups.count
   rejects(.changed,"personal file \(change) refuses stale save"){try stale.save()}
   rejects(.changed,"personal file \(change) refuses stale restore"){try stale.restore(ResidentBackup(url:copy,date:Date()))}
   check(try Data(contentsOf:url.appendingPathComponent("main.dat"))==savedMain,"stale \(change) transaction retains island main")
   check(stale.backups.count==backupsBefore,"stale \(change) transaction publishes no backup")
   if change=="modified" {check(try Data(contentsOf:player)==Data("later progress".utf8),"stale restore retains newer player progress")}
  }
  let full=try ResidentSave(folder:saveURL,catalog:catalog)
  for i in 3..<10 {try full.add(real[10+i],plot:i)}
  check(full.count==10,"all ten slots usable")
  rejects(.full,"eleventh resident refused"){try full.add(real[30],plot:3)}
  try full.save()
  let ten=try ResidentSave(folder:saveURL,catalog:catalog),beforeCycles=ten.plain
  // Reopen a full island so no unused NPC template is available at init.
  for target in real[40..<46] {
   try ten.remove(slot:9);try ten.add(target,plot:9)
   check(ten.count==10 && ten.slots[9].animal==target,"full roster repeated delete and add \(target.id)")
   check(!ten.slots[9].moving,"re-added resident is immediately editable")
   let npc=0x120+9*0x13230
   check(addressingOffsets(npc).union(phraseHistoryOffsets(npc)).allSatisfy{ten.plain[$0]==0},"re-added resident has no old custom speech")
   let changedNPC=npc..<npc+0x13230,changedHouse=ResidentSave.houseBase+9*ResidentSave.houseSize..<ResidentSave.houseBase+10*ResidentSave.houseSize
   check(ten.plain.indices.allSatisfy{ten.plain[$0]==beforeCycles[$0] || changedNPC.contains($0) || changedHouse.contains($0)},"repeated lifecycle retains other residents, buildings and player progress")
  }
  try ten.save()
  let cycleReload=try ResidentSave(folder:saveURL,catalog:catalog)
  check(cycleReload.count==10 && cycleReload.slots[9].animal==real[45],"full roster lifecycle survives encrypted reload")
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
