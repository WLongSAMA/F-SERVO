
import '../utils/ByteDataWrapper.dart';

mixin SimpleComp<T> {
  bool isSame(T other, Map<int, BnkHircChunkBase> hircObjects);
}

abstract class ChunkBase {
  void write(ByteDataWrapper bytes);
}
abstract class BnkChunkBase extends ChunkBase {
  String chunkId;
  int chunkSize;

  BnkChunkBase(this.chunkId, this.chunkSize);

  BnkChunkBase.read(ByteDataWrapper bytes) :
    chunkId = bytes.readString(4),
    chunkSize = bytes.readUint32();

  @override
  void write(ByteDataWrapper bytes) {
    bytes.writeString(chunkId);
    bytes.writeUint32(chunkSize);
  }
}

class BnkFile {
  List<BnkChunkBase> chunks = [];

  BnkFile(this.chunks);

  BnkFile.read(ByteDataWrapper bytes) {
    while (bytes.position < bytes.length) {
      chunks.add(_makeNextChunk(bytes));
    }
  }

  void write(ByteDataWrapper bytes) {
    for (var chunk in chunks) {
      chunk.write(bytes);
    }
  }

  BnkChunkBase _makeNextChunk(ByteDataWrapper bytes) {
    var type = bytes.readString(4);
    bytes.position -= 4;
    switch (type) {
      case "BKHD": return BnkHeader.read(bytes);
      case "DIDX": return BnkDidxChunk.read(bytes);
      case "DATA":
        if (!chunks.any((element) => element is BnkDidxChunk))
          return BnkUnknownChunk.read(bytes);
        var didxChunk = chunks.whereType<BnkDidxChunk>().first;
        return BnkDataChunk.read(bytes, didxChunk);
      case "HIRC": return BnkHircChunk.read(bytes);
      default: return BnkUnknownChunk.read(bytes);
    }
  }
}

class BnkUnknownChunk extends BnkChunkBase {
  late List<int> data;

  BnkUnknownChunk(super.chunkId, super.chunkSize, this.data);

  BnkUnknownChunk.read(ByteDataWrapper bytes) :
    super.read(bytes) {
    data = bytes.readUint8List(chunkSize);
  }

  @override
  void write(ByteDataWrapper bytes) {
    super.write(bytes);
    for (var i = 0; i < data.length; i++)
      bytes.writeUint8(data[i]);
  }
}

class BnkHeader extends BnkChunkBase {
  late int version;
  late int bnkId;
  late int languageId;
  late int isFeedbackInBnk;
  late int projectId;
  late List<int> padding;
  List<int>? unknown;

  BnkHeader(super.chunkId, super.chunkSize, this.version, this.bnkId, this.languageId, this.isFeedbackInBnk, this.projectId, this.padding, [this.unknown]);

  BnkHeader.read(ByteDataWrapper bytes) : super.read(bytes) {
    if (chunkSize < 20) {
      print("Warning: BnkHeader chunk size is less than 20 ($chunkSize)");
      unknown = bytes.readUint8List(chunkSize);
      return;
    }
    version = bytes.readUint32();
    bnkId = bytes.readUint32();
    languageId = bytes.readUint32();
    isFeedbackInBnk = bytes.readUint32();
    projectId = bytes.readUint32();
    padding = bytes.readUint8List(chunkSize - 20);
  }

  @override
  void write(ByteDataWrapper bytes) {
    super.write(bytes);
    if (unknown != null) {
      for (var i = 0; i < unknown!.length; i++)
        bytes.writeUint8(unknown![i]);
      return;
    }
    bytes.writeUint32(version);
    bytes.writeUint32(bnkId);
    bytes.writeUint32(languageId);
    bytes.writeUint32(isFeedbackInBnk);
    bytes.writeUint32(projectId);
    for (var i = 0; i < padding.length; i++)
      bytes.writeUint8(padding[i]);
  }
}

class BnkDidxChunk extends BnkChunkBase {
  late List<BnkWemFileInfo> files;

  BnkDidxChunk(super.chunkId, super.chunkSize, this.files);

  BnkDidxChunk.read(ByteDataWrapper bytes) : super.read(bytes) {
    int childrenCount = chunkSize ~/ 12;
    files = List.generate(childrenCount, (index) => BnkWemFileInfo.read(bytes));
  }

  @override
  void write(ByteDataWrapper bytes) {
    super.write(bytes);
    for (var file in files) {
      file.write(bytes);
    }
  }
}

class BnkWemFileInfo {
  late int id;
  late int offset;
  late int size;

  BnkWemFileInfo(this.id, this.offset, this.size);
  
  BnkWemFileInfo.read(ByteDataWrapper bytes) {
    id = bytes.readUint32();
    offset = bytes.readUint32();
    size = bytes.readUint32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(id);
    bytes.writeUint32(offset);
    bytes.writeUint32(size);
  }
}

class BnkDataChunk extends BnkChunkBase {
  List<List<int>> wemFiles = [];

  BnkDataChunk(super.chunkId, super.chunkSize, this.wemFiles);

  BnkDataChunk.read(ByteDataWrapper bytes, BnkDidxChunk didx) : super.read(bytes) {
    int initialPosition = bytes.position;
    for (var file in didx.files) {
      bytes.position = initialPosition + file.offset;
      wemFiles.add(bytes.readUint8List(file.size));
    }
  }

  @override
  void write(ByteDataWrapper bytes) {
    super.write(bytes);
    int offset = 0;
    int initialPosition = bytes.position;
    for (var file in wemFiles) {
      bytes.position = initialPosition + offset;
      for (var i = 0; i < file.length; i++)
        bytes.writeUint8(file[i]);
      offset += file.length;
      offset = (offset + 15) & ~15;
    }
  }
}

class BnkHircChunk extends BnkChunkBase {
  late List<BnkHircChunkBase> chunks;

  BnkHircChunk(super.chunkId, super.chunkSize, this.chunks);

  BnkHircChunk.read(ByteDataWrapper bytes) : super.read(bytes) {
    int childrenCount = bytes.readUint32();
    chunks = List.generate(childrenCount, (index) => _makeNextHircChunk(bytes));
  }

  @override
  void write(ByteDataWrapper bytes) {
    super.write(bytes);
    bytes.writeUint32(chunks.length);
    for (var chunk in chunks) {
      chunk.write(bytes);
    }
  }
}

enum BnkHircType {
  sound(0x02),
  action(0x03),
  event(0x04),
  musicTrack(0x0B),
  musicSegment(0x0A),
  musicPlaylist(0x0D),
  unknown(-1);

  final int value;
  
  const BnkHircType(this.value);
  static from(int value) => BnkHircType.values.firstWhere((e) => e.value == value, orElse: () => BnkHircType.unknown);
}

abstract class BnkHircChunkBase extends ChunkBase {
  int type;
  int size;
  int uid;
 
  BnkHircChunkBase(this.type, this.size, this.uid);

  BnkHircChunkBase.read(ByteDataWrapper bytes) :
    type = bytes.readUint8(),
    size = bytes.readUint32(),
    uid = bytes.readUint32();
  
  @override
  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(type);
    bytes.writeUint32(size);
    bytes.writeUint32(uid);
  }
}

BnkHircChunkBase _makeNextHircChunk(ByteDataWrapper bytes) {
  var type = bytes.readUint8();
  bytes.position -= 1;
  switch (BnkHircType.from(type)) {
    case BnkHircType.sound:
      return BnkSound.read(bytes);
    case BnkHircType.event:
      return BnkEvent.read(bytes);
    case BnkHircType.action:
      return BnkAction.read(bytes);
    case BnkHircType.musicTrack:
      return BnkMusicTrack.read(bytes);
    case BnkHircType.musicSegment:
      return BnkMusicSegment.read(bytes);
    case BnkHircType.musicPlaylist:
      return BnkMusicPlaylist.read(bytes);
    default: return BnkHircUnknownChunk.read(bytes);
  }
}

class BnkHircUnknownChunk extends BnkHircChunkBase {
  late List<int> data;

  BnkHircUnknownChunk(super.type, super.size, super.uid, this.data);

  BnkHircUnknownChunk.read(ByteDataWrapper bytes) : super.read(bytes) {
    data = bytes.readUint8List(size - 4);
  }

  @override
  void write(ByteDataWrapper bytes) {
    super.write(bytes);
    for (var i = 0; i < data.length; i++)
      bytes.writeUint8(data[i]);
  }
}

class BnkMusicTrack extends BnkHircChunkBase with SimpleComp<BnkMusicTrack> {
  late int uFlags;
  late int numSources;
  late List<BnkSource> sources;
  late int numPlaylistItem;
  late List<BnkPlaylist> playlists;
  int? numSubTrack;
  late int numClipAutomationItem;
  late List<BnkClipAutomation> clipAutomations;
  late BnkNodeBaseParams baseParams;
  late int eTrackType;
  BnkSwitchParams? switchParam;
  BnkTransParams? transParam;
  late int iLookAheadTime;

  BnkMusicTrack(super.chunkId, super.chunkSize, super.type, this.uFlags, this.numSources, this.sources, this.numPlaylistItem, this.playlists, this.numSubTrack, this.numClipAutomationItem, this.clipAutomations, this.baseParams, this.eTrackType, this.switchParam, this.transParam, this.iLookAheadTime);

  BnkMusicTrack.read(ByteDataWrapper bytes) : super.read(bytes) {
    uFlags = bytes.readUint8();
    numSources = bytes.readUint32();
    sources = List.generate(numSources, (index) => BnkSource.read(bytes));
    numPlaylistItem = bytes.readUint32();
    playlists = List.generate(numPlaylistItem, (index) => BnkPlaylist.read(bytes));
    if (numPlaylistItem > 0)
      numSubTrack = bytes.readUint32();
    numClipAutomationItem = bytes.readUint32();
    clipAutomations = List.generate(numClipAutomationItem, (index) => BnkClipAutomation.read(bytes));
    baseParams = BnkNodeBaseParams.read(bytes);
    eTrackType = bytes.readUint8();
    if (eTrackType == 3) {
      switchParam = BnkSwitchParams.read(bytes);
      transParam = BnkTransParams.read(bytes);
    }
    iLookAheadTime = bytes.readUint32();
  }

  @override
  void write(ByteDataWrapper bytes) {
    super.write(bytes);
    bytes.writeUint8(uFlags);
    bytes.writeUint32(numSources);
    for (var i = 0; i < numSources; i++)
      sources[i].write(bytes);
    bytes.writeUint32(numPlaylistItem);
    for (var i = 0; i < numPlaylistItem; i++)
      playlists[i].write(bytes);
    if (numPlaylistItem > 0)
      bytes.writeUint32(numSubTrack!);
    bytes.writeUint32(numClipAutomationItem);
    for (var i = 0; i < numClipAutomationItem; i++)
      clipAutomations[i].write(bytes);
    baseParams.write(bytes);
    bytes.writeUint8(eTrackType);
    if (eTrackType == 3) {
      switchParam!.write(bytes);
      transParam!.write(bytes);
    }
    bytes.writeUint32(iLookAheadTime);
  }

  @override
  bool isSame(BnkMusicTrack other, Map<int, BnkHircChunkBase> hircObjects) {
    return (
      numSources == other.numSources &&
      sources.every((s1) => other.sources.any((s2) => s1.isSame(s2, hircObjects))) &&
      numPlaylistItem == other.numPlaylistItem &&
      playlists.every((p1) => other.playlists.any((p2) => p1.isSame(p2, hircObjects)))
    );
  }

  int calcChunkSize() {
    return (
      4 + // header uid
      1 + // uFlags
      4 + // numSources
      sources.fold<int>(0, (sum, s) => sum + s.calcChunkSize()) +  // sources
      4 + // numPlaylistItem
      playlists.fold<int>(0, (sum, p) => sum + p.calcChunkSize()) +  // playlists
      (numPlaylistItem > 0 ? 4 : 0) + // numSubTrack
      4 + // numClipAutomationItem
      clipAutomations.fold<int>(0, (sum, c) => sum + c.calcChunkSize()) +  // clipAutomations
      baseParams.calcChunkSize() +  // baseParams
      1 + // eTrackType
      (eTrackType == 3 ? switchParam!.calcChunkSize() + transParam!.calcChunkSize() : 0) +  // switchParam, transParam
      4 // iLookAheadTime
    );
  }
}

class BnkMusicSegment extends BnkHircChunkBase with SimpleComp<BnkMusicSegment> {
  late BnkMusicNodeParams musicParams;
  late double fDuration;
  late int ulNumMarkers;
  late List<BnkMusicMarker> wwiseMarkers;

  BnkMusicSegment(super.chunkId, super.chunkSize, super.type, this.musicParams, this.fDuration, this.ulNumMarkers, this.wwiseMarkers);

  BnkMusicSegment.read(ByteDataWrapper bytes) : super.read(bytes) {
    musicParams = BnkMusicNodeParams.read(bytes);
    fDuration = bytes.readFloat64();
    ulNumMarkers = bytes.readUint32();
    wwiseMarkers = List.generate(ulNumMarkers, (index) => BnkMusicMarker.read(bytes));
  }

  @override
  void write(ByteDataWrapper bytes) {
    super.write(bytes);
    musicParams.write(bytes);
    bytes.writeFloat64(fDuration);
    bytes.writeUint32(ulNumMarkers);
    for (var i = 0; i < ulNumMarkers; i++)
      wwiseMarkers[i].write(bytes);
  }

  @override
  bool isSame(BnkMusicSegment other, Map<int, BnkHircChunkBase> hircObjects) {
    return (
      musicParams.isSame(other.musicParams, hircObjects) &&
      fDuration == other.fDuration &&
      ulNumMarkers == other.ulNumMarkers &&
      wwiseMarkers.every((m1) => other.wwiseMarkers.any((m2) => m1.isSame(m2, hircObjects)))
    );
  }
}

class BnkMusicPlaylist extends BnkHircChunkBase with SimpleComp<BnkMusicPlaylist> {
  late BnkMusicTransNodeParams musicTransParams;
  late int numPlaylistItems;
  late List<BnkPlaylistItem> playlistItems;

  BnkMusicPlaylist(super.chunkId, super.chunkSize, super.type, this.musicTransParams, this.numPlaylistItems, this.playlistItems);

  BnkMusicPlaylist.read(ByteDataWrapper bytes) : super.read(bytes) {
    musicTransParams = BnkMusicTransNodeParams.read(bytes);
    numPlaylistItems = bytes.readUint32();
    playlistItems = List.generate(numPlaylistItems, (index) => BnkPlaylistItem.read(bytes));
  }

  @override
  void write(ByteDataWrapper bytes) {
    super.write(bytes);
    musicTransParams.write(bytes);
    bytes.writeUint32(numPlaylistItems);
    for (var i = 0; i < numPlaylistItems; i++)
      playlistItems[i].write(bytes);
  }

  @override
  bool isSame(BnkMusicPlaylist other, Map<int, BnkHircChunkBase> hircObjects) {
    return (
      numPlaylistItems == other.numPlaylistItems &&
      playlistItems.every((p1) => other.playlistItems.any((p2) => p1.isSame(p2, hircObjects)))
    );
  }
}

class BnkPlaylistItem with SimpleComp<BnkPlaylistItem> {
  late int segmentId;
  late int playlistItemId;
  late int numChildren;
  late int eRSType;
  late int loop;
  late int loopMin;
  late int loopMax;
  late int weight;
  late int wAvoidRepeatCount;
  late int bIsUsingWeight;
  late int bIsShuffle;

  BnkPlaylistItem(this.segmentId, this.playlistItemId, this.numChildren, this.eRSType, this.loop, this.loopMin, this.loopMax, this.weight, this.wAvoidRepeatCount, this.bIsUsingWeight, this.bIsShuffle);

  BnkPlaylistItem.read(ByteDataWrapper bytes) {
    segmentId = bytes.readUint32();
    playlistItemId = bytes.readUint32();
    numChildren = bytes.readUint32();
    eRSType = bytes.readInt32();
    loop = bytes.readInt16();
    loopMin = bytes.readInt16();
    loopMax = bytes.readInt16();
    weight = bytes.readUint32();
    wAvoidRepeatCount = bytes.readUint16();
    bIsUsingWeight = bytes.readUint8();
    bIsShuffle = bytes.readUint8();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(segmentId);
    bytes.writeUint32(playlistItemId);
    bytes.writeUint32(numChildren);
    bytes.writeInt32(eRSType);
    bytes.writeInt16(loop);
    bytes.writeInt16(loopMin);
    bytes.writeInt16(loopMax);
    bytes.writeUint32(weight);
    bytes.writeUint16(wAvoidRepeatCount);
    bytes.writeUint8(bIsUsingWeight);
    bytes.writeUint8(bIsShuffle);
  }

  @override
  bool isSame(BnkPlaylistItem other, Map<int, BnkHircChunkBase> hircObjects) {
    return (
      segmentId == 0 && other.segmentId == 0 || (
        hircObjects.containsKey(segmentId) &&
        hircObjects.containsKey(other.segmentId) &&
        (hircObjects[segmentId]! as BnkMusicSegment).isSame((hircObjects[other.segmentId]! as BnkMusicSegment), hircObjects)
      ) &&
      numChildren == other.numChildren
    );
  }
}

class BnkMusicTransNodeParams {
  late BnkMusicNodeParams musicParams;
  late int numRules;
  late List<BnkMusicTransitionRule> rules;

  BnkMusicTransNodeParams(this.musicParams, this.numRules, this.rules);

  BnkMusicTransNodeParams.read(ByteDataWrapper bytes) {
    musicParams = BnkMusicNodeParams.read(bytes);
    numRules = bytes.readUint32();
    rules = List.generate(numRules, (index) => BnkMusicTransitionRule.read(bytes));
  }

  void write(ByteDataWrapper bytes) {
    musicParams.write(bytes);
    bytes.writeUint32(numRules);
    for (var i = 0; i < numRules; i++)
      rules[i].write(bytes);
  }  
}

class BnkMusicTransitionRule {
  late int uNumSrc;
  late List<int> srcNumIDs;
  late int uNumDst;
  late List<int> dstNumIDs;
  late BnkMusicTransSrcRule srcRule;
  late BnkMusicTransDstRule dstRule;
  late int allocTransObjectFlag;
  BnkMusicTransitionObject? musicTransition;

  BnkMusicTransitionRule(this.uNumSrc, this.srcNumIDs, this.uNumDst, this.dstNumIDs, this.srcRule, this.dstRule, this.allocTransObjectFlag, this.musicTransition);

  BnkMusicTransitionRule.read(ByteDataWrapper bytes) {
    uNumSrc = bytes.readUint32();
    srcNumIDs = List.generate(uNumSrc, (index) => bytes.readUint32());
    uNumDst = bytes.readUint32();
    dstNumIDs = List.generate(uNumDst, (index) => bytes.readUint32());
    srcRule = BnkMusicTransSrcRule.read(bytes);
    dstRule = BnkMusicTransDstRule.read(bytes);
    allocTransObjectFlag = bytes.readUint8();
    if (allocTransObjectFlag != 0)
      musicTransition = BnkMusicTransitionObject.read(bytes);
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(uNumSrc);
    for (var i = 0; i < uNumSrc; i++)
      bytes.writeUint32(srcNumIDs[i]);
    bytes.writeUint32(uNumDst);
    for (var i = 0; i < uNumDst; i++)
      bytes.writeUint32(dstNumIDs[i]);
    srcRule.write(bytes);
    dstRule.write(bytes);
    bytes.writeUint8(allocTransObjectFlag);
    if (allocTransObjectFlag != 0)
      musicTransition!.write(bytes);
  }
}

class BnkMusicTransSrcRule {
  late BnkFadeParams fadeParam;
  late int uCueFilterHash;
  late int uJumpToID;
  late int eEntryType;
  late int bPlayPreEntry;
  late int bDestMatchSourceCueName;

  BnkMusicTransSrcRule(this.fadeParam, this.uCueFilterHash, this.uJumpToID, this.eEntryType, this.bPlayPreEntry, this.bDestMatchSourceCueName);

  BnkMusicTransSrcRule.read(ByteDataWrapper bytes) {
    fadeParam = BnkFadeParams.read(bytes);
    uCueFilterHash = bytes.readUint32();
    uJumpToID = bytes.readUint32();
    eEntryType = bytes.readUint16();
    bPlayPreEntry = bytes.readUint8();
    bDestMatchSourceCueName = bytes.readUint8();
  }

  void write(ByteDataWrapper bytes) {
    fadeParam.write(bytes);
    bytes.writeUint32(uCueFilterHash);
    bytes.writeUint32(uJumpToID);
    bytes.writeUint16(eEntryType);
    bytes.writeUint8(bPlayPreEntry);
    bytes.writeUint8(bDestMatchSourceCueName);
  }
}

class BnkMusicTransDstRule {
  late BnkFadeParams fadeParam;
  late int eSyncType;
  late int uCueFilterHash;
  late int bPlayPostExit;

  BnkMusicTransDstRule(this.fadeParam, this.eSyncType, this.uCueFilterHash, this.bPlayPostExit);

  BnkMusicTransDstRule.read(ByteDataWrapper bytes) {
    fadeParam = BnkFadeParams.read(bytes);
    eSyncType = bytes.readUint32();
    uCueFilterHash = bytes.readUint32();
    bPlayPostExit = bytes.readUint8();
  }

  void write(ByteDataWrapper bytes) {
    fadeParam.write(bytes);
    bytes.writeUint32(eSyncType);
    bytes.writeUint32(uCueFilterHash);
    bytes.writeUint8(bPlayPostExit);
  }
}

class BnkMusicTransitionObject {
  late int segmentID;
  late BnkFadeParams fadeInParams;
  late BnkFadeParams fadeOutParams;
  late int playPreEntry;
  late int playPostExit;

  BnkMusicTransitionObject(this.segmentID, this.fadeInParams, this.fadeOutParams, this.playPreEntry, this.playPostExit);

  BnkMusicTransitionObject.read(ByteDataWrapper bytes) {
    segmentID = bytes.readUint32();
    fadeInParams = BnkFadeParams.read(bytes);
    fadeOutParams = BnkFadeParams.read(bytes);
    playPreEntry = bytes.readUint8();
    playPostExit = bytes.readUint8();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(segmentID);
    fadeInParams.write(bytes);
    fadeOutParams.write(bytes);
    bytes.writeUint8(playPreEntry);
    bytes.writeUint8(playPostExit);
  }
}

class BnkMusicMarker with SimpleComp<BnkMusicMarker> {
  late int id;
  late double fPosition;
  late int uStringSize;
  String? pMarkerName;

  BnkMusicMarker(this.id, this.fPosition, this.uStringSize, this.pMarkerName);

  BnkMusicMarker.read(ByteDataWrapper bytes) {
    id = bytes.readUint32();
    fPosition = bytes.readFloat64();
    uStringSize = bytes.readUint32();
    if (uStringSize > 0)
      pMarkerName = bytes.readString(uStringSize);
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(id);
    bytes.writeFloat64(fPosition);
    bytes.writeUint32(uStringSize);
    if (uStringSize > 0)
      bytes.writeString(pMarkerName!);
  }

  @override
  bool isSame(BnkMusicMarker other, Map<int, BnkHircChunkBase> hircObjects) {
    return (
      fPosition == other.fPosition &&
      uStringSize == other.uStringSize &&
      pMarkerName == other.pMarkerName
    );
  }
}

class BnkMusicNodeParams with SimpleComp<BnkMusicNodeParams> {
  late int uFlags;
  late BnkNodeBaseParams baseParams;
  late BnkChildren childrenList;
  late BnkAkMeterInfo meterInfo;
  late int bMeterInfoFlag;
  late int uNumStingers;
  late List<BnkAkStinger> stingers;

  BnkMusicNodeParams(this.uFlags, this.baseParams, this.childrenList, this.meterInfo, this.bMeterInfoFlag, this.uNumStingers, this.stingers);

  BnkMusicNodeParams.read(ByteDataWrapper bytes) {
    uFlags = bytes.readUint8();
    baseParams = BnkNodeBaseParams.read(bytes);
    childrenList = BnkChildren.read(bytes);
    meterInfo = BnkAkMeterInfo.read(bytes);
    bMeterInfoFlag = bytes.readUint8();
    uNumStingers = bytes.readUint32();
    stingers = List.generate(uNumStingers, (index) => BnkAkStinger.read(bytes));
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(uFlags);
    baseParams.write(bytes);
    childrenList.write(bytes);
    meterInfo.write(bytes);
    bytes.writeUint8(bMeterInfoFlag);
    bytes.writeUint32(uNumStingers);
    for (var i = 0; i < uNumStingers; i++)
      stingers[i].write(bytes);
  }

  @override
  bool isSame(BnkMusicNodeParams other, Map<int, BnkHircChunkBase> hircObjects) {
    return (
      childrenList.isSame(other.childrenList, hircObjects)
    );
  }
}

class BnkChildren with SimpleComp<BnkChildren> {
  late int uNumChildren;
  late List<int> ulChildIDs;

  BnkChildren(this.uNumChildren, this.ulChildIDs);

  BnkChildren.read(ByteDataWrapper bytes) {
    uNumChildren = bytes.readUint32();
    ulChildIDs = List.generate(uNumChildren, (index) => bytes.readUint32());
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(uNumChildren);
    for (var i = 0; i < uNumChildren; i++)
      bytes.writeUint32(ulChildIDs[i]);
  }

  @override
  bool isSame(BnkChildren other, Map<int, BnkHircChunkBase> hircObjects) {
    return (
      uNumChildren == other.uNumChildren &&
      (
        uNumChildren == 0 ||
        hircObjects[ulChildIDs[0]] is SimpleComp &&
        (hircObjects[ulChildIDs[0]]! as SimpleComp).isSame(hircObjects[other.ulChildIDs[0]]!, hircObjects)
      )
    );
  }
}

class BnkAkMeterInfo {
  late double fGridPeriod;
  late double fGridOffset;
  late double fTempo;
  late int uNumBeatsPerBar;
  late int uBeatValue;

  BnkAkMeterInfo(this.fGridPeriod, this.fGridOffset, this.fTempo, this.uNumBeatsPerBar, this.uBeatValue);

  BnkAkMeterInfo.read(ByteDataWrapper bytes) {
    fGridPeriod = bytes.readFloat64();
    fGridOffset = bytes.readFloat64();
    fTempo = bytes.readFloat32();
    uNumBeatsPerBar = bytes.readUint8();
    uBeatValue = bytes.readUint8();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeFloat64(fGridPeriod);
    bytes.writeFloat64(fGridOffset);
    bytes.writeFloat32(fTempo);
    bytes.writeUint8(uNumBeatsPerBar);
    bytes.writeUint8(uBeatValue);
  }
}

class BnkAkStinger {
  late int triggerID;
  late int segmentID;
  late int syncPlayAt;
  late int uCueFilterHash;
  late int noRepeatTime;
  late int numSegmentLookAhead;

  BnkAkStinger(this.triggerID, this.segmentID, this.syncPlayAt, this.uCueFilterHash, this.noRepeatTime, this.numSegmentLookAhead);

  BnkAkStinger.read(ByteDataWrapper bytes) {
    triggerID = bytes.readUint32();
    segmentID = bytes.readUint32();
    syncPlayAt = bytes.readUint32();
    uCueFilterHash = bytes.readUint32();
    noRepeatTime = bytes.readInt32();
    numSegmentLookAhead = bytes.readUint32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(triggerID);
    bytes.writeUint32(segmentID);
    bytes.writeUint32(syncPlayAt);
    bytes.writeUint32(uCueFilterHash);
    bytes.writeInt32(noRepeatTime);
    bytes.writeUint32(numSegmentLookAhead);
  }
}

class BnkSource with SimpleComp<BnkSource> {
  late int ulPluginID;
  late int streamType;
  late int sourceID;
  late int uInMemorySize;
  late int uSourceBits;

  BnkSource(this.ulPluginID, this.streamType, this.sourceID, this.uInMemorySize, this.uSourceBits);

  BnkSource.read(ByteDataWrapper bytes) {
    ulPluginID = bytes.readUint32();
    streamType = bytes.readUint8();
    sourceID = bytes.readUint32();
    uInMemorySize = bytes.readUint32();
    uSourceBits = bytes.readUint8();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(ulPluginID);
    bytes.writeUint8(streamType);
    bytes.writeUint32(sourceID);
    bytes.writeUint32(uInMemorySize);
    bytes.writeUint8(uSourceBits);
  }

  @override
  bool isSame(BnkSource other, Map<int, BnkHircChunkBase> hircObjects) {
    return sourceID == other.sourceID;
  }
  
  int calcChunkSize() {
    return 14;
  }
}

class BnkPlaylist with SimpleComp<BnkPlaylist> {
  late int trackID;
  late int sourceID;
  late double fPlayAt;
  late double fBeginTrimOffset;
  late double fEndTrimOffset;
  late double fSrcDuration;

  BnkPlaylist(this.trackID, this.sourceID, this.fPlayAt, this.fBeginTrimOffset, this.fEndTrimOffset, this.fSrcDuration);

  BnkPlaylist.read(ByteDataWrapper bytes) {
    trackID = bytes.readUint32();
    sourceID = bytes.readUint32();
    fPlayAt = bytes.readFloat64();
    fBeginTrimOffset = bytes.readFloat64();
    fEndTrimOffset = bytes.readFloat64();
    fSrcDuration = bytes.readFloat64();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(trackID);
    bytes.writeUint32(sourceID);
    bytes.writeFloat64(fPlayAt);
    bytes.writeFloat64(fBeginTrimOffset);
    bytes.writeFloat64(fEndTrimOffset);
    bytes.writeFloat64(fSrcDuration);
  }

@override
bool isSame(BnkPlaylist other, Map<int, BnkHircChunkBase> hircObjects) {
    return (
      sourceID == other.sourceID &&
      fPlayAt == other.fPlayAt &&
      fBeginTrimOffset == other.fBeginTrimOffset &&
      fEndTrimOffset == other.fEndTrimOffset &&
      fSrcDuration == other.fSrcDuration
    );
  }
  
  int calcChunkSize() {
    return 40;
  }
}

class BnkSwitchParams {
  late int eGroupType;
  late int uGroupID;
  late int uDefaultSwitch;
  late int numSwitchAssoc;
  late List<int> ulSwitchAssoc;

  BnkSwitchParams(this.eGroupType, this.uGroupID, this.uDefaultSwitch, this.numSwitchAssoc, this.ulSwitchAssoc);

  BnkSwitchParams.read(ByteDataWrapper bytes) {
    eGroupType = bytes.readUint8();
    uGroupID = bytes.readUint32();
    uDefaultSwitch = bytes.readUint32();
    numSwitchAssoc = bytes.readUint32();
    ulSwitchAssoc = List.generate(numSwitchAssoc, (index) => bytes.readUint32());
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(eGroupType);
    bytes.writeUint32(uGroupID);
    bytes.writeUint32(uDefaultSwitch);
    bytes.writeUint32(numSwitchAssoc);
    for (var i = 0; i < numSwitchAssoc; i++)
      bytes.writeUint32(ulSwitchAssoc[i]);
  }
  
  int calcChunkSize() {
    return 13 + numSwitchAssoc * 4;
  }
}

class BnkTransParams {
  late BnkFadeParams srcFadeParams;
  late int eSyncType;
  late int uCueHashFilter;
  late BnkFadeParams destFadeParams;

  BnkTransParams(this.srcFadeParams, this.eSyncType, this.uCueHashFilter, this.destFadeParams);

  BnkTransParams.read(ByteDataWrapper bytes) {
    srcFadeParams = BnkFadeParams.read(bytes);
    eSyncType = bytes.readUint32();
    uCueHashFilter = bytes.readUint32();
    destFadeParams = BnkFadeParams.read(bytes);
  }

  void write(ByteDataWrapper bytes) {
    srcFadeParams.write(bytes);
    bytes.writeUint32(eSyncType);
    bytes.writeUint32(uCueHashFilter);
    destFadeParams.write(bytes);
  }
  
  int calcChunkSize() {
    return 12 + 4 + 4 + 12;
  }
}

class BnkFadeParams {
  late int transitionTime;
  late int eFadeCurve;
  late int iFadeOffset;

  BnkFadeParams(this.transitionTime, this.eFadeCurve, this.iFadeOffset);

  BnkFadeParams.read(ByteDataWrapper bytes) {
    transitionTime = bytes.readInt32();
    eFadeCurve = bytes.readUint32();
    iFadeOffset = bytes.readInt32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeInt32(transitionTime);
    bytes.writeUint32(eFadeCurve);
    bytes.writeInt32(iFadeOffset);
  }
}

class BnkRtpcGraphPoint {
  late double to;
  late double from;
  late int interpolation;

  BnkRtpcGraphPoint(this.to, this.from, this.interpolation);

  BnkRtpcGraphPoint.read(ByteDataWrapper bytes) {
    to = bytes.readFloat32();
    from = bytes.readFloat32();
    interpolation = bytes.readUint32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeFloat32(to);
    bytes.writeFloat32(from);
    bytes.writeUint32(interpolation);
  }
  
  int calcChunkSize() {
    return 4 + 4 + 4;
  }
}


class BnkClipAutomation {
  late int uClipIndex;
  late int eAutoType;
  late int uNumPoints;
  late List<BnkRtpcGraphPoint> rtpcGraphPoint;

  BnkClipAutomation(this.uClipIndex, this.eAutoType, this.uNumPoints, this.rtpcGraphPoint);

  BnkClipAutomation.read(ByteDataWrapper bytes) {
    uClipIndex = bytes.readUint32();
    eAutoType = bytes.readUint32();
    uNumPoints = bytes.readUint32();
    rtpcGraphPoint = List.generate(uNumPoints, (index) => BnkRtpcGraphPoint.read(bytes));
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(uClipIndex);
    bytes.writeUint32(eAutoType);
    bytes.writeUint32(uNumPoints);
    for (var i = 0; i < uNumPoints; i++)
      rtpcGraphPoint[i].write(bytes);
  }
  
  int calcChunkSize() {
    return 12 + uNumPoints * 12;
  }
}

class BnkPropValue {
  late int cProps;
  late List<int> pID;
  late List<int> pValueBytes;

  BnkPropValue(this.cProps, this.pID, this.pValueBytes);

  BnkPropValue.read(ByteDataWrapper bytes) {
    cProps = bytes.readUint8();
    pID = List.generate(cProps, (index) => bytes.readUint8());
    pValueBytes = List.generate(cProps*4, (index) => bytes.readUint8());
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(cProps);
    for (var i = 0; i < cProps; i++)
      bytes.writeUint8(pID[i]);
    for (var b in pValueBytes)
      bytes.writeUint8(b);
  }
  
  int calcChunkSize() {
    return 1 + cProps + cProps * 4;
  }
}

class BnkPropRangedValue {
  late int cProps;
  late List<int> pID;
  late List<double> minMax;

  BnkPropRangedValue(this.cProps, this.pID, this.minMax);

  BnkPropRangedValue.read(ByteDataWrapper bytes) {
    cProps = bytes.readUint8();
    pID = List.generate(cProps, (index) => bytes.readUint8());
    minMax = List.generate(cProps*2, (index) => bytes.readFloat32());
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(cProps);
    for (var i = 0; i < cProps; i++)
      bytes.writeUint8(pID[i]);
    for (var i = 0; i < cProps*2; i++)
      bytes.writeFloat32(minMax[i]);
  }
  
  int calcChunkSize() {
    return 1 + cProps + cProps * 8;
  }
}


class BnkNodeInitialParams {
  late BnkPropValue propValues;
  late BnkPropRangedValue rangedPropValues;

  BnkNodeInitialParams(this.propValues, this.rangedPropValues);

  BnkNodeInitialParams.read(ByteDataWrapper bytes) {
    propValues = BnkPropValue.read(bytes);
    rangedPropValues = BnkPropRangedValue.read(bytes);
  }

  void write(ByteDataWrapper bytes) {
    propValues.write(bytes);
    rangedPropValues.write(bytes);
  }
  
  int calcChunkSize() {
    return propValues.calcChunkSize() + rangedPropValues.calcChunkSize();
  }
}

class BnkFxChunk {
  late int uFXIndex;
  late int fxID;
  late int bIsShareSet;
  late int bIsRendered;

  BnkFxChunk(this.uFXIndex, this.fxID, this.bIsShareSet, this.bIsRendered);

  BnkFxChunk.read(ByteDataWrapper bytes) {
    uFXIndex = bytes.readUint8();
    fxID = bytes.readUint32();
    bIsShareSet = bytes.readUint8();
    bIsRendered = bytes.readUint8();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(uFXIndex);
    bytes.writeUint32(fxID);
    bytes.writeUint8(bIsShareSet);
    bytes.writeUint8(bIsRendered);
  }
}

class BnkNodeInitialFXParams {
  late int bIsOverrideParentFX;
  late int uNumFX;
  int? bitsFXBypass;
  late List<BnkFxChunk> effect;

  BnkNodeInitialFXParams(this.bIsOverrideParentFX, this.uNumFX, this.bitsFXBypass, this.effect);

  BnkNodeInitialFXParams.read(ByteDataWrapper bytes) {
    bIsOverrideParentFX = bytes.readUint8();
    uNumFX = bytes.readUint8();
    if (uNumFX > 0)
      bitsFXBypass = bytes.readUint8();
    effect = List.generate(uNumFX, (index) => BnkFxChunk.read(bytes));
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(bIsOverrideParentFX);
    bytes.writeUint8(uNumFX);
    if (uNumFX > 0)
      bytes.writeUint8(bitsFXBypass!);
    for (var i = 0; i < uNumFX; i++)
      effect[i].write(bytes);
  }
  
  int calcChunkSize() {
    return 2 + (uNumFX > 0 ? 1 : 0) + uNumFX * 7;
  }
}

class BnkPathVertex {
  late double x, y, z;
  late int duration;

  BnkPathVertex(this.x, this.y, this.z, this.duration);

  BnkPathVertex.read(ByteDataWrapper bytes) {
    x = bytes.readFloat32();
    y = bytes.readFloat32();
    z = bytes.readFloat32();
    duration = bytes.readUint32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeFloat32(x);
    bytes.writeFloat32(y);
    bytes.writeFloat32(z);
    bytes.writeUint32(duration);
  }
}

class PathListItemOffset {
  late int verticesOffset;
  late int verticesCount;

  PathListItemOffset(this.verticesOffset, this.verticesCount);

  PathListItemOffset.read(ByteDataWrapper bytes) {
    verticesOffset = bytes.readUint32();
    verticesCount = bytes.readUint32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(verticesOffset);
    bytes.writeUint32(verticesCount);
  }
}

class Bnk3DAutomationParams {
  late double xRange, yRange, zRange;

  Bnk3DAutomationParams(this.xRange, this.yRange, this.zRange);

  Bnk3DAutomationParams.read(ByteDataWrapper bytes) {
    xRange = bytes.readFloat32();
    yRange = bytes.readFloat32();
    zRange = bytes.readFloat32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeFloat32(xRange);
    bytes.writeFloat32(yRange);
    bytes.writeFloat32(zRange);
  }
}

class BnkPositioningParams {
  late int uBitsPositioning;
  int has3D = 0;
  int? uBits3D;
  int? attenuationID;
  bool hasAutomation = false;
  int? pathMode;
  int? transitionTime;
  int? numVertices;
  List<BnkPathVertex>? vertices;
  int? numPlayListItem;
  List<PathListItemOffset>? playListItems;
  List<Bnk3DAutomationParams>? params;

  BnkPositioningParams.read(ByteDataWrapper bytes) {
    uBitsPositioning = bytes.readUint8();
    var hasPositioning = (uBitsPositioning >> 0) & 1;
    has3D = hasPositioning == 1 ? (uBitsPositioning >> 3) & 1 : 0;
    if (has3D == 1) {
      uBits3D = bytes.readUint8();
      attenuationID = bytes.readUint32();

      var e3DPositionType = (uBits3D! >> 0) & 3;
      hasAutomation = e3DPositionType != 1;

      if (hasAutomation) {
        pathMode = bytes.readUint8();
        transitionTime = bytes.readUint32();

        numVertices = bytes.readUint32();
        vertices = List.generate(numVertices!, (index) => BnkPathVertex.read(bytes));

        numPlayListItem = bytes.readUint32();
        playListItems = List.generate(numPlayListItem!, (index) => PathListItemOffset.read(bytes));
        params = List.generate(numPlayListItem!, (index) => Bnk3DAutomationParams.read(bytes));
      }
    }
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(uBitsPositioning);
    if (has3D == 1) {
      bytes.writeUint8(uBits3D!);
      bytes.writeUint32(attenuationID!);

      if (hasAutomation) {
        bytes.writeUint8(pathMode!);
        bytes.writeUint32(transitionTime!);

        bytes.writeUint32(numVertices!);
        for (var element in vertices!)
          element.write(bytes);

        bytes.writeUint32(numPlayListItem!);
        for (var element in playListItems!)
          element.write(bytes);
        for (var element in params!)
          element.write(bytes);
      }
    }
  }

  int calcChunkSize() {
    return (
      1 + // uBitsPositioning
      (has3D == 1 ? (
        1 + // uBits3D
        4 + // attenuationID
        (hasAutomation ? (
          1 + // pathMode
          4 + // transitionTime
          4 + // numVertices
          numVertices! * 16 + // vertices
          4 + // numPlayListItem
          numPlayListItem! * 8 + // playListItems
          numPlayListItem! * 12 // params
        ) : 0)
      ) : 0)
    );
  }
}

class BnkAuxParams {
  late int byBitVector;
  int? auxID1;
  int? auxID2;
  int? auxID3;
  int? auxID4;

  BnkAuxParams(this.byBitVector, this.auxID1, this.auxID2, this.auxID3, this.auxID4);

  BnkAuxParams.read(ByteDataWrapper bytes) {
    byBitVector = bytes.readUint8();
    var hasAux = (byBitVector >> 3) & 1;
    if (hasAux == 1) {
      auxID1 = bytes.readUint32();
      auxID2 = bytes.readUint32();
      auxID3 = bytes.readUint32();
      auxID4 = bytes.readUint32();
    }
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(byBitVector);
    if (auxID1 != null && auxID2 != null && auxID3 != null && auxID4 != null) {
      bytes.writeUint32(auxID1!);
      bytes.writeUint32(auxID2!);
      bytes.writeUint32(auxID3!);
      bytes.writeUint32(auxID4!);
    }
  }
  
  int calcChunkSize() {
    return 1 + (auxID1 != null && auxID2 != null && auxID3 != null && auxID4 != null ? 16 : 0);
  }
}

class BnkAdvSettingsParams {
  late int byBitVector1;
  late int eVirtualQueueBehavior;
  late int uMaxNumInstance;
  late int eBelowThresholdBehavior;
  late int byBitVector2;

  BnkAdvSettingsParams(this.byBitVector1, this.eVirtualQueueBehavior, this.uMaxNumInstance, this.eBelowThresholdBehavior, this.byBitVector2);

  BnkAdvSettingsParams.read(ByteDataWrapper bytes) {
    byBitVector1 = bytes.readUint8();
    eVirtualQueueBehavior = bytes.readUint8();
    uMaxNumInstance = bytes.readUint16();
    eBelowThresholdBehavior = bytes.readUint8();
    byBitVector2 = bytes.readUint8();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(byBitVector1);
    bytes.writeUint8(eVirtualQueueBehavior);
    bytes.writeUint16(uMaxNumInstance);
    bytes.writeUint8(eBelowThresholdBehavior);
    bytes.writeUint8(byBitVector2);
  }
  
  int calcChunkSize() {
    return 6;
  }
}

class BnkStateChunk {
  late int ulNumStateGroups;
  late List<BnkStateGroup> stateGroup;

  BnkStateChunk(this.ulNumStateGroups, this.stateGroup);

  BnkStateChunk.read(ByteDataWrapper bytes) {
    ulNumStateGroups = bytes.readUint32();
    stateGroup = List.generate(ulNumStateGroups, (index) => BnkStateGroup.read(bytes));
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(ulNumStateGroups);
    for (var i = 0; i < ulNumStateGroups; i++)
      stateGroup[i].write(bytes);
  }
  
  int calcChunkSize() {
    return 4 + stateGroup.fold<int>(0, (previousValue, element) => previousValue + element.calcChunkSize());
  }
}
class BnkStateGroup {
  late int ulStateGroupID;
  late int eStateSyncType;
  late int ulNumStates;
  late List<BnkState> state;

  BnkStateGroup(this.ulStateGroupID, this.eStateSyncType, this.ulNumStates, this.state);

  BnkStateGroup.read(ByteDataWrapper bytes) {
    ulStateGroupID = bytes.readUint32();
    eStateSyncType = bytes.readUint8();
    ulNumStates = bytes.readUint16();
    state = List.generate(ulNumStates, (index) => BnkState.read(bytes));
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(ulStateGroupID);
    bytes.writeUint8(eStateSyncType);
    bytes.writeUint16(ulNumStates);
    for (var i = 0; i < ulNumStates; i++)
      state[i].write(bytes);
  }
  
  int calcChunkSize() {
    return 7 + state.fold<int>(0, (previousValue, element) => previousValue + element.calcChunkSize());
  }
}
class BnkState {
  late int ulStateID;
  late int ulStateInstanceID;

  BnkState(this.ulStateID, this.ulStateInstanceID);

  BnkState.read(ByteDataWrapper bytes) {
    ulStateID = bytes.readUint32();
    ulStateInstanceID = bytes.readUint32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(ulStateID);
    bytes.writeUint32(ulStateInstanceID);
  }
  
  int calcChunkSize() {
    return 8;
  }
}

class BnkInitialRTPC {
  late int ulInitialRTPC;
  late List<BnkRtpc> rtpc;

  BnkInitialRTPC(this.ulInitialRTPC, this.rtpc);

  BnkInitialRTPC.read(ByteDataWrapper bytes) {
    ulInitialRTPC = bytes.readUint16();
    rtpc = List.generate(ulInitialRTPC, (index) => BnkRtpc.read(bytes));
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint16(ulInitialRTPC);
    for (var i = 0; i < ulInitialRTPC; i++)
      rtpc[i].write(bytes);
  }
  
  int calcChunkSize() {
    return 2 + rtpc.fold<int>(0, (previousValue, element) => previousValue + element.calcChunkSize());
  }
}
class BnkRtpc {
  late int rtpcId;
  late int rtpcType;
  late int rtpcAcc;
  late int paramID;
  late int rtpcCurveID;
  late int eScaling;
  late int ulSize;
  late List<BnkRtpcGraphPoint> rtpcGraphPoint;

  BnkRtpc(this.rtpcId, this.rtpcType, this.rtpcAcc, this.paramID, this.rtpcCurveID, this.eScaling, this.ulSize, this.rtpcGraphPoint);

  BnkRtpc.read(ByteDataWrapper bytes) {
    rtpcId = bytes.readUint32();
    rtpcType = bytes.readUint8();
    rtpcAcc = bytes.readUint8();
    paramID = bytes.readUint8();
    rtpcCurveID = bytes.readUint32();
    eScaling = bytes.readUint8();
    ulSize = bytes.readUint16();
    rtpcGraphPoint = List.generate(ulSize, (index) => BnkRtpcGraphPoint.read(bytes));
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(rtpcId);
    bytes.writeUint8(rtpcType);
    bytes.writeUint8(rtpcAcc);
    bytes.writeUint8(paramID);
    bytes.writeUint32(rtpcCurveID);
    bytes.writeUint8(eScaling);
    bytes.writeUint16(ulSize);
    for (var i = 0; i < ulSize; i++)
      rtpcGraphPoint[i].write(bytes);
  }
  
  int calcChunkSize() {
    return 14 + rtpcGraphPoint.fold<int>(0, (previousValue, element) => previousValue + element.calcChunkSize());
  }
}

class BnkNodeBaseParams {
  late BnkNodeInitialFXParams fxParams;
  late int bOverrideAttachmentParams;
  late int overrideBusID;
  late int directParentID;
  late int byBitVector;
  late BnkNodeInitialParams iniParams;
  late BnkPositioningParams positioning;
  late BnkAuxParams auxParam;
  late BnkAdvSettingsParams advSettings;
  late BnkStateChunk states;
  late BnkInitialRTPC rtpc;

  BnkNodeBaseParams(this.fxParams, this.bOverrideAttachmentParams, this.overrideBusID, this.directParentID, this.byBitVector, this.iniParams, this.positioning, this.auxParam, this.advSettings, this.states, this.rtpc);

  BnkNodeBaseParams.read(ByteDataWrapper bytes) {
    fxParams = BnkNodeInitialFXParams.read(bytes);
    bOverrideAttachmentParams = bytes.readUint8();
    overrideBusID = bytes.readUint32();
    directParentID = bytes.readUint32();
    byBitVector = bytes.readUint8();
    iniParams = BnkNodeInitialParams.read(bytes);
    positioning = BnkPositioningParams.read(bytes);
    auxParam = BnkAuxParams.read(bytes);
    advSettings = BnkAdvSettingsParams.read(bytes);
    states = BnkStateChunk.read(bytes);
    rtpc = BnkInitialRTPC.read(bytes);
  }

  void write(ByteDataWrapper bytes) {
    fxParams.write(bytes);
    bytes.writeUint8(bOverrideAttachmentParams);
    bytes.writeUint32(overrideBusID);
    bytes.writeUint32(directParentID);
    bytes.writeUint8(byBitVector);
    iniParams.write(bytes);
    positioning.write(bytes);
    auxParam.write(bytes);
    advSettings.write(bytes);
    states.write(bytes);
    rtpc.write(bytes);
  }
  
  int calcChunkSize() {
    return (
      fxParams.calcChunkSize() +
      1 +
      4 +
      4 +
      1 +
      iniParams.calcChunkSize() +
      positioning.calcChunkSize() +
      auxParam.calcChunkSize() +
      advSettings.calcChunkSize() +
      states.calcChunkSize() +
      rtpc.calcChunkSize()
    );
  }
}

class BnkEvent extends BnkHircChunkBase {
  late int ulActionListSize;
  late List<int> ids;

  BnkEvent(super.chunkId, super.chunkSize, super.type, this.ulActionListSize, this.ids);

  BnkEvent.read(ByteDataWrapper bytes) : super.read(bytes) {
    ulActionListSize = bytes.readUint32();
    ids = List.generate(ulActionListSize, (index) => bytes.readUint32());
  }

  void write(ByteDataWrapper bytes) {
    super.write(bytes);
    bytes.writeUint32(ulActionListSize);
    for (var i = 0; i < ulActionListSize; i++)
      bytes.writeUint32(ids[i]);
  }
  
  int calcChunkSize() {
    return 4 + ulActionListSize * 4;
  }
}

class BnkSound extends BnkHircChunkBase {
  late BnkSourceData bankData;
  late BnkNodeBaseParams baseParams;

  BnkSound(super.chunkId, super.chunkSize, super.type, this.bankData, this.baseParams);

  BnkSound.read(ByteDataWrapper bytes) : super.read(bytes) {
    bankData = BnkSourceData.read(bytes);
    baseParams = BnkNodeBaseParams.read(bytes);
  }

  void write(ByteDataWrapper bytes) {
    super.write(bytes);
    bankData.write(bytes);
    baseParams.write(bytes);
  }
  
  int calcChunkSize() {
    return bankData.calcChunkSize() + baseParams.calcChunkSize();
  }
}

class BnkSourceData {
  late int ulPluginID;
  late int streamType;
  late BnkMediaInformation mediaInformation;
  late int uSize;

  BnkSourceData(this.ulPluginID, this.streamType, this.mediaInformation, this.uSize);

  BnkSourceData.read(ByteDataWrapper bytes) {
    ulPluginID = bytes.readUint32();
    streamType = bytes.readUint8();
    mediaInformation = BnkMediaInformation.read(bytes);
    if ((ulPluginID & 0x000000FF) == 2) {
      uSize = bytes.readUint32();
    }
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(ulPluginID);
    bytes.writeUint8(streamType);
    mediaInformation.write(bytes);
    if ((ulPluginID & 0x000000FF) == 2) {
      bytes.writeUint32(uSize);
    }
  }
  
  int calcChunkSize() {
    return 5 + mediaInformation.calcChunkSize() + ((ulPluginID & 0x000000FF) == 2 ? 4 : 0);
  }
}

class BnkMediaInformation {
  late int sourceID;
  late int uInMemoryMediaSize;
  late int uSourceBits;

  BnkMediaInformation(this.sourceID, this.uInMemoryMediaSize, this.uSourceBits);

  BnkMediaInformation.read(ByteDataWrapper bytes) {
    sourceID = bytes.readUint32();
    uInMemoryMediaSize = bytes.readUint32();
    uSourceBits = bytes.readUint8();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(sourceID);
    bytes.writeUint32(uInMemoryMediaSize);
    bytes.writeUint8(uSourceBits);
  }
  
  int calcChunkSize() {
    return 9;
  }
}

class BnkExceptParams {
  late int ulExceptionListSize;
  late List<int> ids;
  late List<int> isBus;

  BnkExceptParams(this.ulExceptionListSize, this.ids, this.isBus);

  BnkExceptParams.read(ByteDataWrapper bytes) {
    ulExceptionListSize = bytes.readUint32();
    ids = List.filled(ulExceptionListSize, 0);
    isBus = List.filled(ulExceptionListSize, 0);
    for (var i = 0; i < ulExceptionListSize; i++) {
      ids[i] = bytes.readUint32();
      isBus[i] = bytes.readUint8();
    }
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(ulExceptionListSize);
    for (var i = 0; i < ulExceptionListSize; i++) {
      bytes.writeUint32(ids[i]);
      bytes.writeUint8(isBus[i]);
    }
  }
  
  int calcChunkSize() {
    return 4 + ulExceptionListSize * 5;
  }
}

class BnkStateActionParams {
  late int ulStateGroupID;
  late int ulTargetStateID;

  BnkStateActionParams(this.ulStateGroupID, this.ulTargetStateID);

  BnkStateActionParams.read(ByteDataWrapper bytes) {
    ulStateGroupID = bytes.readUint32();
    ulTargetStateID = bytes.readUint32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(ulStateGroupID);
    bytes.writeUint32(ulTargetStateID);
  }
  
  int calcChunkSize() {
    return 8;
  }
}

class BnkSwitchActionParams {
  late int ulSwitchGroupID;
  late int ulSwitchStateID;

  BnkSwitchActionParams(this.ulSwitchGroupID, this.ulSwitchStateID);

  BnkSwitchActionParams.read(ByteDataWrapper bytes) {
    ulSwitchGroupID = bytes.readUint32();
    ulSwitchStateID = bytes.readUint32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(ulSwitchGroupID);
    bytes.writeUint32(ulSwitchStateID);
  }
  
  int calcChunkSize() {
    return 8;
  }
}

const _activeActionAdditionalActionTypes = {0x403, 0x503, 0x202, 0x203, 0x204, 0x205, 0x208, 0x209, 0x302, 0x303, 0x304, 0x305, 0x308, 0x309};
class BnkActiveActionParams {
  late int byBitVector;
  int? byBitVector2;
  late BnkExceptParams exceptions;

  BnkActiveActionParams(this.byBitVector, this.exceptions);

  BnkActiveActionParams.read(ByteDataWrapper bytes, int actionType) {
    byBitVector = bytes.readUint8();
    if (_activeActionAdditionalActionTypes.contains(actionType))
      byBitVector2 = bytes.readUint8();
    exceptions = BnkExceptParams.read(bytes);
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(byBitVector);
    if (byBitVector2 != null)
      bytes.writeUint8(byBitVector2!);
    exceptions.write(bytes);
  }
  
  int calcChunkSize() {
    return 1 + exceptions.calcChunkSize();
  }
}

class BnkGameParameterParams {
  late int bBypassTransition;
  late int eValueMeaning;
  late double base;
  late double min;
  late double max;

  BnkGameParameterParams(this.bBypassTransition, this.eValueMeaning, this.base, this.min, this.max);

  BnkGameParameterParams.read(ByteDataWrapper bytes) {
    bBypassTransition = bytes.readUint8();
    eValueMeaning = bytes.readUint8();
    base = bytes.readFloat32();
    min = bytes.readFloat32();
    max = bytes.readFloat32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(bBypassTransition);
    bytes.writeUint8(eValueMeaning);
    bytes.writeFloat32(base);
    bytes.writeFloat32(min);
    bytes.writeFloat32(max);
  }
  
  int calcChunkSize() {
    return 1*2 + 3*4;
  }
}

class BnkPropActionParams {
  late int eValueMeaning;
  late double base;
  late double min;
  late double max;

  BnkPropActionParams(this.eValueMeaning, this.base, this.min, this.max);

  BnkPropActionParams.read(ByteDataWrapper bytes) {
    eValueMeaning = bytes.readUint8();
    base = bytes.readFloat32();
    min = bytes.readFloat32();
    max = bytes.readFloat32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(eValueMeaning);
    bytes.writeFloat32(base);
    bytes.writeFloat32(min);
    bytes.writeFloat32(max);
  }
  
  int calcChunkSize() {
    return 1 + 3*4;
  }
}

const _gameParamActionTypes = {0x1302, 0x1303, 0x1402, 0x1403};
const _propActionActionTypes = {0x0A02, 0x0A03, 0x0A04, 0x0A05, 0x0B02, 0x0B03, 0x0B04, 0x0B05, 0x0C02, 0x0C03, 0x0C04, 0x0C05, 0x0D02, 0x0D03, 0x0D04, 0x0D05, 0x0802, 0x0803, 0x0804, 0x0805, 0x0902, 0x0903, 0x0904, 0x0905, 0x0F02, 0x0F03, 0x0F04, 0x0F05, 0x0E02, 0x0E03, 0x0E04, 0x0E05, 0x2002, 0x2003, 0x2004, 0x2005, 0x3002, 0x3003, 0x3004, 0x3005};
class BnkValueActionParams {
  late int byBitVector;
  late Object? specificParams;
  late int ulExceptionListSize;

  BnkValueActionParams(this.byBitVector, this.specificParams, this.ulExceptionListSize);

  BnkValueActionParams.read(ByteDataWrapper bytes, int ulActionType) {
    byBitVector = bytes.readUint8();
    if (_gameParamActionTypes.contains(ulActionType)) {
      specificParams = BnkGameParameterParams.read(bytes);
    } else if (_propActionActionTypes.contains(ulActionType)) {
      specificParams = BnkPropActionParams.read(bytes);
    }
    ulExceptionListSize = bytes.readUint32();
  }

  void write(ByteDataWrapper bytes, int ulActionType) {
    bytes.writeUint8(byBitVector);
    if (_gameParamActionTypes.contains(ulActionType)) {
      (specificParams! as BnkGameParameterParams).write(bytes);
    } else if (_propActionActionTypes.contains(ulActionType)) {
      (specificParams! as BnkPropActionParams).write(bytes);
    }
    bytes.writeUint32(ulExceptionListSize);
  }
  
  // int calcChunkSize(int ulActionType) {
  //   return 1 + (specificParams! as dynamic).calcChunkSize() + 4;
  // }
}

class BnkPlayActionParams {
  late int eFadeCurve;
  late int fileID;

  BnkPlayActionParams(this.eFadeCurve, this.fileID);

  BnkPlayActionParams.read(ByteDataWrapper bytes) {
    eFadeCurve = bytes.readUint8();
    fileID = bytes.readUint32();
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(eFadeCurve);
    bytes.writeUint32(fileID);
  }
  
  int calcChunkSize() {
    return 1 + 4;
  }
}

class BnkBypassFXActionParams {
  late int bIsBypass;
  late int uTargetMask;
  late BnkExceptParams exceptions;

  BnkBypassFXActionParams(this.bIsBypass, this.uTargetMask, this.exceptions);

  BnkBypassFXActionParams.read(ByteDataWrapper bytes) {
    bIsBypass = bytes.readUint8();
    uTargetMask = bytes.readUint8();
    exceptions = BnkExceptParams.read(bytes);
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint8(bIsBypass);
    bytes.writeUint8(uTargetMask);
    exceptions.write(bytes);
  }
  
  int calcChunkSize() {
    return 1*2 + exceptions.calcChunkSize();
  }
}

class BnkActionInitialParams {
  late int idExt;
  late int idExt_4;
  late BnkPropValue propValues;
  late BnkPropRangedValue rangedPropValues;

  BnkActionInitialParams(this.idExt, this.idExt_4, this.propValues, this.rangedPropValues);

  BnkActionInitialParams.read(ByteDataWrapper bytes) {
    idExt = bytes.readUint32();
    idExt_4 = bytes.readUint8();
    propValues = BnkPropValue.read(bytes);
    rangedPropValues = BnkPropRangedValue.read(bytes);
  }

  void write(ByteDataWrapper bytes) {
    bytes.writeUint32(idExt);
    bytes.writeUint8(idExt_4);
    propValues.write(bytes);
    rangedPropValues.write(bytes);
  }
  
  int calcChunkSize() {
    return 4 + 1 + propValues.calcChunkSize() + rangedPropValues.calcChunkSize();
  }
}

const _activeActionParamsActionsTypes = {0x0102, 0x0103, 0x0104, 0x0105, 0x0202, 0x0203, 0x0204, 0x0205, 0x0302, 0x0303, 0x0304, 0x0305};
const _bypassFXActionParamsActionsTypes = {0x1A02, 0x1A03};
const _valueActionParamsActionsTypes = {0x1302, 0x1303, 0x1402, 0x1403, 0x0602, 0x0603, 0x0604, 0x0605, 0x0F02, 0x0F03, 0x0F04, 0x0F05, 0x0E02, 0x0E03, 0x0E04, 0x0E05, 0x0702, 0x0703, 0x0704, 0x0705, 0x0802, 0x0803, 0x0804, 0x0805, 0x0902, 0x0903, 0x0904, 0x0905, 0x0A02, 0x0A03, 0x0A04, 0x0A05, 0x0B02, 0x0B03, 0x0B04, 0x0B05, 0x0C02, 0x0C03, 0x0C04, 0x0C05, 0x0D02, 0x0D03, 0x0D04, 0x0D05, 0x2002, 0x2003, 0x2004, 0x2005, 0x3002, 0x3003, 0x3004, 0x3005};
class BnkAction extends BnkHircChunkBase {
  late int ulActionType;
  late BnkActionInitialParams initialParams;
  late dynamic specificParams;

  BnkAction(super.chunkId, super.chunkSize, super.type, this.ulActionType, this.initialParams, this.specificParams);

  BnkAction.read(ByteDataWrapper bytes) : super.read(bytes) {
    ulActionType = bytes.readUint16();
    initialParams = BnkActionInitialParams.read(bytes);
    if (ulActionType == 0x1204) {
      specificParams = BnkStateActionParams.read(bytes);
    } else if (_activeActionParamsActionsTypes.contains(ulActionType)) {
      specificParams = BnkActiveActionParams.read(bytes, ulActionType);
    } else if (ulActionType == 0x0403) {
      specificParams = BnkPlayActionParams.read(bytes);
    } else if (_bypassFXActionParamsActionsTypes.contains(ulActionType)) {
      specificParams = BnkBypassFXActionParams.read(bytes);
    } else if (_valueActionParamsActionsTypes.contains(ulActionType)) {
      specificParams = BnkValueActionParams.read(bytes, ulActionType);
    }
  }

  @override
  void write(ByteDataWrapper bytes) {
    super.write(bytes);
    bytes.writeUint16(ulActionType);
    initialParams.write(bytes);
    if (ulActionType == 0x1204) {
      (specificParams as BnkStateActionParams).write(bytes);
    } else if (_activeActionParamsActionsTypes.contains(ulActionType)) {
      (specificParams as BnkActiveActionParams).write(bytes);
    } else if (ulActionType == 0x0403) {
      (specificParams as BnkPlayActionParams).write(bytes);
    } else if (_bypassFXActionParamsActionsTypes.contains(ulActionType)) {
      (specificParams as BnkBypassFXActionParams).write(bytes);
    } else if (_valueActionParamsActionsTypes.contains(ulActionType)) {
      (specificParams as BnkValueActionParams).write(bytes, ulActionType);
    }
  }

  int calcChunkSize() {
    return 2 + initialParams.calcChunkSize();
  }
}

