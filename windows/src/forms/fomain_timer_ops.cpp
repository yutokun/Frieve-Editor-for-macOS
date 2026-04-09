// ---------------------------------------------------------------------------
// Timer helper operations split from fomain_timer.cpp

#include <vcl.h>
#pragma hdrstop

#include "fomain_timer_ops.h"

#include "fomain.h"
#include "fofullscreen.h"
#include "setting.h"
#include "utils.h"

namespace {

void RelayoutFilePanels(TFo_Main *mainForm) {
  mainForm->Ti_Check->Enabled = false;
  Application->ProcessMessages(); // Let components resize
  mainForm->Ti_Check->Enabled = true;
}

void PreserveSelectionAfterAutoReload(TFo_Main *mainForm) {
  int prevTargetCard = mainForm->m_nTargetCard;
  mainForm->LoadSub(mainForm->m_Document->m_FN, true);
  if (prevTargetCard >= 0 &&
      mainForm->m_Document->SearchCardIndex(prevTargetCard) >= 0) {
    mainForm->m_nTargetCard = prevTargetCard;
  } else {
    mainForm->m_nTargetCard = -1;
  }

  mainForm->m_Document->ClearCardSelection();
  if (mainForm->m_nTargetCard >= 0) {
    TCard *Card = mainForm->m_Document->GetCard(mainForm->m_nTargetCard);
    if (Card) {
      Card->m_bSelected = true;
    }
  }
}

void ShowFileListPanel(TFo_Main *mainForm) {
  mainForm->CloseEditBox();
  mainForm->PB_Browser->Tag = 1;

  mainForm->Pa_Client->Visible = false;
  mainForm->Sp_Left2->Visible = false;
  mainForm->Pa_List->Visible = false;
  mainForm->Pa_Client->Align = alNone;
  mainForm->Sp_Left2->Align = alNone;
  mainForm->Pa_List->Align = alNone;

  mainForm->Pa_Files->Visible = true;
  mainForm->Sp_Left->Left = mainForm->Pa_Files->Width;
  mainForm->Sp_Left->Visible = true;

  RelayoutFilePanels(mainForm);

  mainForm->Pa_List->Left = mainForm->Pa_Files->Width + mainForm->Sp_Left->Width;
  mainForm->Pa_List->Align = alLeft;
  mainForm->Sp_Left2->Left = mainForm->Pa_List->Left + mainForm->Pa_List->Width;
  mainForm->Sp_Left2->Align = alLeft;
  mainForm->Pa_Client->Left = mainForm->Sp_Left2->Left + mainForm->Sp_Left2->Width;
  mainForm->Pa_Client->Width = mainForm->ClientWidth - mainForm->Pa_Client->Left;
  mainForm->Pa_Client->Align = alClient;
  mainForm->Pa_List->Visible = true;
  mainForm->Sp_Left2->Visible = true;
  mainForm->Pa_Client->Visible = true;

  RelayoutFilePanels(mainForm);

  mainForm->PB_Browser->Tag = 0;
}

void HideFileListPanel(TFo_Main *mainForm) {
  mainForm->PB_Browser->Tag = 1;

  mainForm->Pa_Client->Visible = false;
  mainForm->Sp_Left2->Visible = false;
  mainForm->Pa_List->Visible = false;
  mainForm->Pa_Client->Align = alNone;
  mainForm->Sp_Left2->Align = alNone;
  mainForm->Pa_List->Align = alNone;

  mainForm->Pa_Files->Visible = false;
  mainForm->Sp_Left->Visible = false;

  mainForm->Pa_List->Left = 0;
  mainForm->Pa_List->Align = alLeft;
  mainForm->Sp_Left2->Left = mainForm->Pa_List->Left + mainForm->Pa_List->Width;
  mainForm->Sp_Left2->Align = alLeft;
  mainForm->Pa_Client->Left = mainForm->Sp_Left2->Left + mainForm->Sp_Left2->Width;
  mainForm->Pa_Client->Width = mainForm->ClientWidth - mainForm->Pa_Client->Left;
  mainForm->Pa_Client->Align = alClient;
  mainForm->Pa_List->Visible = true;
  mainForm->Sp_Left2->Visible = true;
  mainForm->Pa_Client->Visible = true;

  RelayoutFilePanels(mainForm);

  mainForm->PB_Browser->Tag = 0;
}

} // namespace

namespace FomainTimerOps {

void HandleContinuousLoad(TFo_Main *mainForm) {
  if (!mainForm->m_bContinuousLoad) {
    return;
  }

  int newage = FileAge(mainForm->m_Document->m_FN);
  if (newage != mainForm->m_nCLFileAge) {
    mainForm->LoadSub(mainForm->m_Document->m_FN, true);
  }
}

void HandleAutoReload(TFo_Main *mainForm, unsigned int tick) {
  if (!mainForm->m_Document || mainForm->m_Document->m_FN == "" ||
      mainForm->m_bContinuousLoad || mainForm->m_Document->m_nAutoReload == 0) {
    return;
  }

  int pollSec = SettingFile.m_nAutoReloadPollSec;
  if (pollSec < 1) {
    pollSec = 1;
  }

  unsigned int pollMs = (unsigned int)pollSec * 1000u;
  if (mainForm->m_uLastAutoReloadCheckTick != 0 &&
      tick - mainForm->m_uLastAutoReloadCheckTick < pollMs) {
    return;
  }

  mainForm->m_uLastAutoReloadCheckTick = tick;
  int newage = FileAge(mainForm->m_Document->m_FN);
  if (newage == mainForm->m_nAutoReloadFileAge || newage == -1) {
    return;
  }

  if (!mainForm->m_Document->m_bChanged) {
    PreserveSelectionAfterAutoReload(mainForm);
  } else {
    mainForm->m_nAutoReloadFileAge = newage;
  }
}

void HandleAutoSave(TFo_Main *mainForm, unsigned int tick) {
  if (!mainForm->m_Document || mainForm->m_Document->m_FN == "" ||
      mainForm->m_Document->m_bReadOnly || mainForm->m_Document->m_nAutoSave == 0 ||
      !mainForm->m_Document->m_bChanged) {
    return;
  }

  int idleSec = SettingFile.m_nAutoSaveIdleSec;
  if (idleSec < 0) {
    idleSec = 0;
  }
  int minSec = SettingFile.m_nAutoSaveMinIntervalSec;
  if (minSec < 1) {
    minSec = 1;
  }

  unsigned int idleMs = (unsigned int)idleSec * 1000u;
  unsigned int minMs = (unsigned int)minSec * 1000u;
  bool idleEnough = (tick - mainForm->m_uLastUserEditTick >= idleMs);
  bool intervalEnough =
      (mainForm->m_uLastAutoSaveTick == 0 ||
       tick - mainForm->m_uLastAutoSaveTick >= minMs);

  if (idleEnough && intervalEnough && mainForm->Save()) {
    mainForm->m_uLastAutoSaveTick = tick;
    mainForm->m_nAutoReloadFileAge = FileAge(mainForm->m_Document->m_FN);
  }
}

void HandlePluginTimeout(TFo_Main *mainForm) {
  if (SettingFile.fepTimeOut) {
    SettingFile.fepTimeOut(mainForm->m_Document);
  }
}

void ApplyDefaultView(TFo_Main *mainForm) {
  if (mainForm->m_Document->m_nDefaultView < 0) {
    return;
  }

  switch (mainForm->m_Document->m_nDefaultView) {
  case 0:
    mainForm->PC_Client->ActivePage = mainForm->TS_Browser;
    break;
  case 1:
    mainForm->PC_Client->ActivePage = mainForm->TS_Editor;
    break;
  }
  mainForm->m_Document->m_nDefaultView = -1;
}

bool ApplyOperationRequests(TFo_Main *mainForm, TObject *Sender) {
  if (fReqZoom >= -999.0f) {
    mainForm->TB_Zoom->Position = (int)(fReqZoom * 2000);
    fReqZoom = -1000.0f;
  }
  if (fReqX >= -999.0f) {
    if (mainForm->PC_Client->ActivePage != mainForm->TS_Browser) {
      mainForm->Sc_X->Position = (int)(fReqX * 10000);
    } else {
      mainForm->m_fBrowserScrollRatio = 0.0f;
      mainForm->m_nScrollTargetX = fReqX * 10000;
    }
    fReqX = -1000.0f;
  }
  if (fReqY >= -999.0f) {
    if (mainForm->PC_Client->ActivePage != mainForm->TS_Browser) {
      mainForm->Sc_Y->Position = (int)(fReqY * 10000);
    } else {
      mainForm->m_fBrowserScrollRatio = 0.0f;
      mainForm->m_nScrollTargetY = fReqY * 10000;
    }
    fReqY = -1000.0f;
  }
  if (bReqArrange != -1) {
    mainForm->SB_Arrange->Down = bReqArrange;
    bReqArrange = -1;
  }
  if (nReqArrangeMode != -1) {
    mainForm->Bu_ArrangeType->Tag = nReqArrangeMode;
    nReqArrangeMode = -1;
  }
  if (bReqAutoScroll != -1) {
    mainForm->SB_AutoScroll->Down = bReqAutoScroll;
    bReqAutoScroll = -1;
  }
  if (bReqAutoZoom != -1) {
    mainForm->SB_AutoZoom->Down = bReqAutoZoom;
    bReqAutoZoom = -1;
  }
  if (bReqFullScreen != -1) {
    if (bReqFullScreen != Fo_FullScreen->Visible) {
      mainForm->MV_FullScreenClick(Sender);
    }
    bReqFullScreen = -1;
  }
  if (bReqExit != -1) {
    mainForm->Close();
    return true;
  }
  if (nReqTargetCard != -1000) {
    mainForm->m_nTargetCard = nReqTargetCard;
    nReqTargetCard = -1000;
  }
  if (bReqSizeLimitation != -1) {
    SettingView.m_bSizeLimitation = bReqSizeLimitation;
    bReqSizeLimitation = -1;
  }
  if (bReqLinkLimitation != -1) {
    SettingView.m_bLinkLimitation = bReqLinkLimitation;
    bReqLinkLimitation = -1;
  }
  if (bReqDateLimitation != -1) {
    SettingView.m_bDateLimitation = bReqDateLimitation;
    bReqDateLimitation = -1;
  }
  if (nReqSizeLimitation != -1) {
    SettingView.m_nSizeLimitation = nReqSizeLimitation;
    nReqSizeLimitation = -1;
  }
  if (nReqLinkLimitation != -1) {
    SettingView.m_nLinkLimitation = nReqLinkLimitation;
    nReqLinkLimitation = -1;
  }
  if (bReqLinkDirection != -1) {
    SettingView.m_bLinkDirection = bReqLinkDirection;
    bReqLinkDirection = -1;
  }
  if (bReqLinkBackward != -1) {
    SettingView.m_bLinkBackward = bReqLinkBackward;
    bReqLinkBackward = -1;
  }
  if (nReqLinkTarget != -2) {
    SettingView.m_nLinkTarget = nReqLinkTarget;
    nReqLinkTarget = -2;
  }
  if (nReqDateLimitation != -1) {
    SettingView.m_nDateLimitation = nReqDateLimitation;
    nReqDateLimitation = -1;
  }
  if (ReqDateLimitationDateType != -1) {
    SettingView.m_DateLimitationDateType = ReqDateLimitationDateType;
    ReqDateLimitationDateType = -1;
  }
  if (ReqDateLimitationType != -1) {
    SettingView.m_DateLimitationType = ReqDateLimitationType;
    ReqDateLimitationType = -1;
  }
  if (nReqKeyDown != -1) {
    unsigned short Key = (unsigned short)nReqKeyDown;
    mainForm->FormKeyDown(Sender, Key, TShiftState());
    nReqKeyDown = -1;
  }

  return false;
}

void UpdateWindowTitles(TFo_Main *mainForm) {
  UnicodeString appTitle;
  if (mainForm->m_Document->m_FN != "") {
    appTitle = ExtractFileNameOnly(mainForm->m_Document->m_FN);
  } else {
    appTitle = AppTitle;
  }
  if (Application->Title != appTitle) {
    Application->Title = appTitle;
  }

  UnicodeString caption;
  if (SettingView.m_nSpecialPaint) {
    caption = SettingView.m_SpecialCaption;
  } else {
    caption = UnicodeString(AppTitle) + " " + mainForm->m_Document->m_FN;
    if (mainForm->m_Document->m_bChanged) {
      caption += " *";
    }
  }
  if (mainForm->Caption != caption) {
    mainForm->Caption = caption;
  }
}

void UpdateFileListPanel(TFo_Main *mainForm) {
  TPoint pos, listpos;
  GetCursorPos(&pos);
  listpos.x = mainForm->Pa_Files->Left;
  listpos.y = mainForm->Pa_Files->Top;
  listpos = mainForm->ClientToScreen(listpos);

  if (pos.x >= mainForm->Left && pos.x < mainForm->Left + mainForm->Width &&
      pos.y >= mainForm->Top && pos.y < mainForm->Top + mainForm->Height) {
    bool shouldShow =
        (pos.x < mainForm->Left + 16 && pos.y >= listpos.y &&
         pos.y < listpos.y + mainForm->Pa_List->Height) &&
        !mainForm->Pa_Files->Visible && mainForm->m_nAnimation == 0 &&
        Application->Active && !mainForm->m_bMDownBrowser &&
        SettingView.m_bFileList;
    bool shouldHide =
        (pos.x >= mainForm->Left + mainForm->Pa_List->Left + 32 ||
         pos.y < listpos.y || pos.y > listpos.y + mainForm->Pa_Files->Height ||
         !Application->Active) &&
        mainForm->Pa_Files->Visible;

    if (shouldShow) {
      ShowFileListPanel(mainForm);
    } else if (shouldHide) {
      HideFileListPanel(mainForm);
    }
  }

  TColor c = (TColor)SettingView.m_nBackgroundColor;
  if (mainForm->m_Document->m_bChanged) {
    c = clBtnFace;
  }
  if (mainForm->LB_FileList->Color != c) {
    mainForm->LB_FileList->Color = c;
  }
}

} // namespace FomainTimerOps

#pragma package(smart_init)
