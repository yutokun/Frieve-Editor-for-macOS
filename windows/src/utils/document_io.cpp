// ---------------------------------------------------------------------------
// Document file I/O implementation split from document.cpp

#pragma hdrstop

#include <IniFiles.hpp>
#include <System.IOUtils.hpp>
#include <string.h>

#include "document.h"
#include "utils.h"

bool TDocument::LoadFromString(TStringList *SL, UnicodeString FN) {
  bool result = true;

  if (ShouldLoadAsFip2(FN, SL)) {
    return LoadFromStringFip2(SL, FN);
  }

  // Save
  ClearCards();
  ClearLinks();
  ClearLabels(0);
  ClearLabels(1);

  int line = 1;
  while (line < SL->Count) {
    if (SL->Strings[line++] == "[CardData]") {
      break;
    }
  }

  TStringList *SL2 = new TStringList();
  for (int i = 0; i < line - 1; i++) {
    SL2->Add(SL->Strings[i]);
  }
  TFastIni *Ini = new TFastIni(SL2);

  int version = Ini->ReadInteger("Global", "Version", 0);

  if (version <= 0) {
    delete Ini;
    delete SL2;
    if (FN != "") {
      return Load_Old(FN);
    } else {
      return false;
    }
  }

  // Load
  m_bReadOnly = Ini->ReadBool("Global", "ReadOnly", 0);
  m_nDefaultView = Ini->ReadInteger("Global", "DefaultView", -1);

  // Backward compatibility:
  // If an existing .fip has no AutoSave/AutoReload entries, treat them as OFF.
  // Compatibility:
  // Missing keys in older files mean OFF(0). If keys exist, follow 0/1.
  // Any non-zero value is treated as ON.
  m_nAutoSave = Ini->ReadInteger("Global", "AutoSave", 0) != 0 ? 1 : 0;
  m_nAutoReload = Ini->ReadInteger("Global", "AutoReload", 0) != 0 ? 1 : 0;

  // Card order
  bReqArrange = Ini->ReadInteger("Global", "Arrange", bReqArrange);
  // Arrange ON/OFF
  nReqArrangeMode =
      Ini->ReadInteger("Global", "ArrangeMode",
                       nReqArrangeMode); // 0=Repulsion, Link, Label, Index
  bReqAutoScroll = Ini->ReadInteger("Global", "AutoScroll",
                                    bReqAutoScroll); // Auto scroll
  bReqAutoZoom = Ini->ReadInteger("Global", "AutoZoom", bReqAutoZoom);
  // Auto zoom
  bReqFullScreen = Ini->ReadInteger("Global", "FullScreen",
                                    bReqFullScreen);       // Full screen
  bReqExit = Ini->ReadInteger("Global", "Exit", bReqExit); // Exit
  fReqZoom = Ini->ReadFloat("Global", "Zoom", fReqZoom);
  fReqX = Ini->ReadFloat("Global", "X", fReqX);
  fReqY = Ini->ReadFloat("Global", "Y", fReqY);
  nReqTargetCard = Ini->ReadInteger("Global", "TargetCard", nReqTargetCard);
  bReqSizeLimitation =
      Ini->ReadInteger("Global", "SizeLimitation", bReqSizeLimitation);
  bReqLinkLimitation =
      Ini->ReadInteger("Global", "LinkLimitation", bReqLinkLimitation);
  bReqDateLimitation =
      Ini->ReadInteger("Global", "DateLimitation", bReqDateLimitation);
  nReqSizeLimitation =
      Ini->ReadInteger("Global", "SizeLimitation", nReqSizeLimitation);
  nReqLinkLimitation =
      Ini->ReadInteger("Global", "LinkLimitation", nReqLinkLimitation);
  bReqLinkDirection =
      Ini->ReadInteger("Global", "LinkDirection", bReqLinkDirection);
  bReqLinkBackward =
      Ini->ReadInteger("Global", "LinkBackward", bReqLinkBackward);
  nReqLinkTarget = Ini->ReadInteger("Global", "LinkTarget", nReqLinkTarget);
  nReqDateLimitation =
      Ini->ReadInteger("Global", "DateLimitation", nReqDateLimitation);
  ReqDateLimitationDateType = Ini->ReadInteger(
      "Global", "DateLimitationDateType", ReqDateLimitationDateType);
  ReqDateLimitationType =
      Ini->ReadInteger("Global", "DateLimitationType", ReqDateLimitationType);

  // Card ID check
  int cardnum = Ini->ReadInteger("Card", "Num", 0);
  m_nCardID = Ini->ReadInteger("Card", "CardID", -1);

  int maxid = 0;
  for (int i = 0; i < cardnum; i++) {
    // TCard *Card = NewCard(m_Cards->Count);
    TCard *Card = new TCard();
    m_Cards->Add(Card);
    Card->m_nID = Ini->ReadInteger("Card", IntToStr(i), 0);
    if (Card->m_nID > maxid) {
      maxid = Card->m_nID;
    }
  }

  m_nMaxCardID = maxid + 1;

  // Link check
  int linknum = Ini->ReadInteger("Link", "Num", 0);
  for (int i = 0; i < linknum; i++) {
    TLink *Link = NewLink();
    if (version < 6) {
      Link->Decode_005(Ini->ReadString("Link", IntToStr(i), ""));
    } else if (version < 7) {
      Link->Decode_006(Ini->ReadString("Link", IntToStr(i), ""));
    } else {
      Link->Decode(Ini->ReadString("Link", IntToStr(i), ""));
    }
  }

  // Label check
  int labelnum = Ini->ReadInteger("Label", "Num", -1);
  if (labelnum < 0) {
    InitLabel(0);
  } else {
    for (int i = 0; i < labelnum; i++) {
      TCardLabel *Label = NewLabel(0);
      switch (version) {
      case 0:
      case 1:
        Label->Decode_001(Ini->ReadString("Label", IntToStr(i), ""));
        break;
      case 2:
        Label->Decode_002(Ini->ReadString("Label", IntToStr(i), ""));
        break;
      case 3:
        Label->Decode_003(Ini->ReadString("Label", IntToStr(i), ""));
        break;
      case 4:
      case 5:
      case 6:
        Label->Decode_006(Ini->ReadString("Label", IntToStr(i), ""));
        break;
      default:
        Label->Decode(Ini->ReadString("Label", IntToStr(i), ""));
      }
    }
  }

  // Label check
  labelnum = Ini->ReadInteger("LinkLabel", "Num", -1);
  if (labelnum < 0) {
    InitLabel(1);
  } else {
    for (int i = 0; i < labelnum; i++) {
      TCardLabel *Label = NewLabel(1);
      switch (version) {
      case 0:
      case 1:
        Label->Decode_001(Ini->ReadString("LinkLabel", IntToStr(i), ""));
        break;
      case 2:
        Label->Decode_002(Ini->ReadString("LinkLabel", IntToStr(i), ""));
        break;
      case 3:
        Label->Decode_003(Ini->ReadString("LinkLabel", IntToStr(i), ""));
        break;
      case 4:
      case 5:
      case 6:
        Label->Decode_006(Ini->ReadString("LinkLabel", IntToStr(i), ""));
        break;
      default:
        Label->Decode(Ini->ReadString("LinkLabel", IntToStr(i), ""));
      }
    }
  }

  delete Ini;
  delete SL2;

  for (int i = 0; i < cardnum; i++) {
    TCard *Card = GetCardByIndex_(i);
    Card->LoadFromString(SL, line, version);
  }

  return result;
}

// ---------------------------------------------------------------------------
bool TDocument::SoftLoadFromString(TStringList *SL, UnicodeString FN) {
  // 20070804 test_continuousload.fip compatibility

  // Label, link limitation, link limitation check
  // Card and file path value

  bool result = true;
  ClearLinks();

  TDocument *Tmp = new TDocument();
  result &= Tmp->LoadFromString(SL, FN);

  // Card path, file path
  for (int i = 0; i < m_Cards->Count; i++) {
    TCard *Card = GetCardByIndex(i);
    TCard *Card2 = Tmp->GetCard(Card->m_nID);
    if (Card2) {
      Card2->m_fX = Card->m_fX;
      Card2->m_fY = Card->m_fY;
      Card2->m_fCreated = Card->m_fCreated;
      Card2->m_fUpdated = Card->m_fUpdated;
      Card2->m_fViewed = Card->m_fViewed;
    }
  }
  // Card load
  ClearCards();
  int maxid = 0;
  for (int i = 0; i < Tmp->m_Cards->Count; i++) {
    TCard *Card2 = Tmp->GetCardByIndex(i);
    // TCard *Card = NewCard(m_Cards->Count);
    TCard *Card = new TCard();
    m_Cards->Add(Card);
    Card->m_nID = Card2->m_nID;
    TStringList *SL2 = new TStringList();
    Card2->SaveToString(SL2);
    int line = 0;
    Card->LoadFromString(SL2, line, FileVersion);

    if (Card->m_nID > maxid) {
      maxid = Card->m_nID;
    }
  }

  m_nMaxCardID = maxid + 1;

  // Link load
  for (int i = 0; i < Tmp->m_Links->Count; i++) {
    TLink *Link = NewLink();
    Link->Decode(Tmp->GetLinkByIndex(i)->Encode());
  }

  // Label parameter check
  for (int il = 0; il < 2; il++) {
    for (int i = 0; i < Tmp->m_Labels[il]->Count; i++) {
      TCardLabel *Label2 = Tmp->GetLabelByIndex(il, i);
      TCardLabel *Label = GetLabel(il, Label2->m_Name);
      if (Label) {
        Label2->m_bEnable = Label->m_bEnable;
        Label2->m_bFold = Label->m_bFold;
        Label2->m_bShow = Label->m_bShow;
        Label2->m_bHide = Label->m_bHide;
      }
    }
  }

  // Label load
  ClearLabels(0);
  ClearLabels(1);
  for (int il = 0; il < 2; il++) {
    for (int i = 0; i < Tmp->m_Labels[il]->Count; i++) {
      TCardLabel *Label = NewLabel(il);
      Label->Decode(Tmp->GetLabelByIndex(il, i)->Encode());
    }
  }

  delete Tmp;

  return result;
}

// ---------------------------------------------------------------------------
bool TDocument::SaveToString(TStringList *SL) {
  bool result = true;

  SL->Add("[Global]");
  SL->Add(UnicodeString("Version=") + IntToStr(FileVersion));

  // Always store explicit values (0/1). If keys are absent in older files,
  // LoadFromString will treat them as OFF(0) for compatibility.
  SL->Add(UnicodeString("AutoSave=") + IntToStr(m_nAutoSave));
  SL->Add(UnicodeString("AutoReload=") + IntToStr(m_nAutoReload));

  // Read
  SL->Add(UnicodeString("Arrange=") + IntToStr(bReqArrange)); // Arrange ON/OFF
  SL->Add(UnicodeString("ArrangeMode=") + IntToStr(nReqArrangeMode));
  // 0=Repulsion, Link, Label, Index
  SL->Add(UnicodeString("AutoScroll=") + IntToStr(bReqAutoScroll));
  // Auto scroll
  SL->Add(UnicodeString("AutoZoom=") + IntToStr(bReqAutoZoom)); // Auto zoom
  SL->Add(UnicodeString("FullScreen=") +
          IntToStr(bReqFullScreen));                    // Full screen
  SL->Add(UnicodeString("Exit=") + IntToStr(bReqExit)); // Exit
  SL->Add(UnicodeString("Zoom=") + FloatToStr(fReqZoom));
  SL->Add(UnicodeString("X=") + FloatToStr(fReqX));
  SL->Add(UnicodeString("Y=") + FloatToStr(fReqY));
  SL->Add(UnicodeString("TargetCard=") + IntToStr(nReqTargetCard));
  SL->Add(UnicodeString("SizeLimitation=") + IntToStr(bReqSizeLimitation));
  SL->Add(UnicodeString("LinkLimitation=") + IntToStr(bReqLinkLimitation));
  SL->Add(UnicodeString("DateLimitation=") + IntToStr(bReqDateLimitation));
  SL->Add(UnicodeString("SizeLimitation=") + IntToStr(nReqSizeLimitation));
  SL->Add(UnicodeString("LinkLimitation=") + IntToStr(nReqLinkLimitation));
  SL->Add(UnicodeString("LinkDirection=") + IntToStr(bReqLinkDirection));
  SL->Add(UnicodeString("LinkBackward=") + IntToStr(bReqLinkBackward));
  SL->Add(UnicodeString("LinkTarget=") + IntToStr(nReqLinkTarget));
  SL->Add(UnicodeString("DateLimitation=") + IntToStr(nReqDateLimitation));
  SL->Add(UnicodeString("DateLimitationDateType=") +
          IntToStr(ReqDateLimitationDateType));
  SL->Add(UnicodeString("DateLimitationType=") +
          IntToStr(ReqDateLimitationType));

  // Card ID
  SL->Add("[Card]");
  SL->Add(UnicodeString("CardID=") + m_nCardID);
  SL->Add(UnicodeString("Num=") + m_Cards->Count);
  for (int i = 0; i < m_Cards->Count; i++) {
    SL->Add(IntToStr(i) + UnicodeString("=") + GetCardByIndex_(i)->m_nID);
  }

  // Link
  SL->Add("[Link]");
  SL->Add(UnicodeString("Num=") + m_Links->Count);
  for (int i = 0; i < m_Links->Count; i++) {
    SL->Add(IntToStr(i) + UnicodeString("=") + GetLinkByIndex(i)->Encode());
  }

  // Label
  SL->Add("[Label]");
  SL->Add(UnicodeString("Num=") + m_Labels[0]->Count);
  for (int i = 0; i < m_Labels[0]->Count; i++) {
    SL->Add(IntToStr(i) + UnicodeString("=") + GetLabelByIndex(0, i)->Encode());
  }

  // Label
  SL->Add("[LinkLabel]");
  SL->Add(UnicodeString("Num=") + m_Labels[1]->Count);
  for (int i = 0; i < m_Labels[1]->Count; i++) {
    SL->Add(IntToStr(i) + UnicodeString("=") + GetLabelByIndex(1, i)->Encode());
  }

  // Parent card path
  SL->Add("[CardData]");
  for (int i = 0; i < m_Cards->Count; i++) {
    TCard *Card = GetCardByIndex_(i);
    Card->SaveToString(SL);
  }

  return result;
}

// ---------------------------------------------------------------------------
// FIP2 is always UTF-8 (optional BOM). Do not use legacy .fip heuristics
// (e.g. Shift-JIS fallback) for .fip2 or files whose first non-empty line is
// FIP2/1 or FIPMD/1 in UTF-8.
static bool Fip2LoadMustUseUtf8(const UnicodeString &FN, const TBytes &b) {
  if (LowerCase(ExtractFileExt(FN)) == UnicodeString(L".fip2")) {
    return true;
  }
  int start = 0;
  int n = b.Length;
  if (n >= 3 && (unsigned char)b[0] == 0xEF && (unsigned char)b[1] == 0xBB &&
      (unsigned char)b[2] == 0xBF) {
    start = 3;
  }
  while (start < n) {
    unsigned char c = (unsigned char)b[start];
    if (c == ' ' || c == '\t') {
      start++;
      continue;
    }
    if (c == '\r') {
      start++;
      if (start < n && (unsigned char)b[start] == '\n') {
        start++;
      }
      continue;
    }
    if (c == '\n') {
      start++;
      continue;
    }
    static const char m1[] = "FIP2/1";
    static const char m2[] = "FIPMD/1";
    if (start + (int)sizeof(m1) - 1 <= n &&
        memcmp(&b[start], m1, sizeof(m1) - 1) == 0) {
      return true;
    }
    if (start + (int)sizeof(m2) - 1 <= n &&
        memcmp(&b[start], m2, sizeof(m2) - 1) == 0) {
      return true;
    }
    break;
  }
  return false;
}

// ---------------------------------------------------------------------------
bool TDocument::Load(UnicodeString FN, bool bSoftLoad) {
  bool result = true;

  m_FN = FN;
  if (!FileExists(FN)) {
    return false;
  }

  TStringList *SL = new TStringList();
  try {
    TBytes buffer = TFile::ReadAllBytes(m_FN);
    TEncoding *enc = nullptr;
    if (Fip2LoadMustUseUtf8(m_FN, buffer)) {
      enc = TEncoding::UTF8;
    } else {
      // Legacy .fip: UTF-8 with BOM or Shift-JIS (and similar)
      TEncoding::GetBufferEncoding(buffer, enc, TEncoding::GetEncoding(932));
    }
    if (enc == nullptr) {
      enc = TEncoding::UTF8;
    }
    TMemoryStream *stream = new TMemoryStream();
    if (buffer.Length > 0) {
      stream->WriteBuffer(&buffer[0], buffer.Length);
      stream->Position = 0;
    }
    SL->LoadFromStream(stream, enc);
    delete stream;
    if (bSoftLoad) {
      SoftLoadFromString(SL, m_FN);
    } else {
      LoadFromString(SL, m_FN);
    }
    m_bChanged = false;
  } catch (...) {
    result = false;
  }
  delete SL;

  // File path required (essential)
  if (SearchCardIndex(m_nCardID) == -1) {
    m_nCardID = -1;
  }

  return result;
}

// ---------------------------------------------------------------------------
bool TDocument::Save() {
  bool result;

  // Global data
  TStringList *SL = new TStringList();

  UnicodeString ext = LowerCase(ExtractFileExt(m_FN));
  if (ext == L".fip") {
    result = SaveToString(SL);
  } else {
    // FIP2: UTF-8 without BOM (see FIP2_FORMAT_SPEC.md)
    result = SaveToStringFip2(SL);
  }

  try {
    // .fip may write UTF-8 with BOM; .fip2 and other extensions: UTF-8, no BOM
    SL->WriteBOM = (ext == L".fip");
    SL->SaveToFile(m_FN, TEncoding::UTF8);
  } catch (...) {
    result = false;
  }

  delete SL;

  if (result) {
    m_bChanged = false;
  }
  return result;
}

// ---------------------------------------------------------------------------
bool TDocument::Load_Old(UnicodeString FN) {
  m_FN = FN;

  // Save
  ClearCards();
  ClearLinks();

  ClearLabels(0);
  ClearLabels(1);

  // Parent card path folder
  UnicodeString Dir =
      m_FN.SubString(1, m_FN.Length() - ExtractFileExt(m_FN).Length());

  // Card ID check
  TIniFile *Ini = new TIniFile(m_FN);
  int cardnum = Ini->ReadInteger("Card", "Num", 0);
  m_nCardID = -1;

  int maxid = 0;
  for (int i = 0; i < cardnum; i++) {
    // TCard *Card = NewCard(m_Cards->Count);
    TCard *Card = new TCard();
    m_Cards->Add(Card);
    Card->m_nID = Ini->ReadInteger("Card", IntToStr(i), 0);
    if (Card->m_nID > maxid) {
      maxid = Card->m_nID;
    }
    Card->LoadFromFile(Dir + "\\" + IntToDigit(Card->m_nID, 8) + ".txt");
  }

  m_nMaxCardID = maxid + 1;

  // Link check
  int linknum = Ini->ReadInteger("Link", "Num", 0);
  for (int i = 0; i < linknum; i++) {
    TLink *Link = NewLink();
    Link->Decode(Ini->ReadString("Link", IntToStr(i), ""));
  }

  // Label check
  int labelnum = Ini->ReadInteger("Label", "Num", -1);
  if (labelnum < 0) {
    InitLabel(0);
  } else {
    for (int i = 0; i < labelnum; i++) {
      TCardLabel *Label = NewLabel(0);
      Label->Decode_Old(Ini->ReadString("Label", IntToStr(i), ""));
    }
  }

  delete Ini;

  m_bChanged = false;
  return true;
}

// ---------------------------------------------------------------------------
bool TDocument::Save_Old() {
  TIniFile *Ini = new TIniFile(m_FN);

  // Card ID
  Ini->WriteInteger("Card", "Num", m_Cards->Count);
  for (int i = 0; i < m_Cards->Count; i++) {
    Ini->WriteInteger("Card", IntToStr(i), GetCardByIndex_(i)->m_nID);
  }

  // Link
  Ini->WriteInteger("Link", "Num", m_Links->Count);
  for (int i = 0; i < m_Links->Count; i++) {
    Ini->WriteString("Link", IntToStr(i), GetLinkByIndex(i)->Encode());
  }

  // Label
  Ini->WriteInteger("Label", "Num", m_Labels[0]->Count);
  for (int i = 0; i < m_Labels[0]->Count; i++) {
    Ini->WriteString("Label", IntToStr(i), GetLabelByIndex(0, i)->Encode());
  }

  delete Ini;

  // Parent card path folder
  UnicodeString Dir =
      m_FN.SubString(1, m_FN.Length() - ExtractFileExt(m_FN).Length());
  if (!DirectoryExists(Dir)) {
    MkDir(Dir);
  }

  // Parent card path
  for (int i = 0; i < m_Cards->Count; i++) {
    TCard *Card = GetCardByIndex_(i);
    Card->SaveToFile(Dir + "\\" + IntToDigit(Card->m_nID, 8) + ".txt");
  }

  m_bChanged = false;
  return true;
}

#pragma package(smart_init)
