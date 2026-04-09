// ---------------------------------------------------------------------------

#pragma hdrstop

#include "document.h"

// Request
int bReqArrange = -1;
int nReqArrangeMode = -1;
int bReqAutoScroll = -1;
int bReqAutoZoom = -1;
int bReqFullScreen = -1;
int bReqExit = -1;
float fReqZoom = -1000.0f, fReqX = -1000.0f,
      fReqY = -1000.0f;     // Zoom center coordinates
int nReqTargetCard = -1000; // Target card change
int bReqSizeLimitation = -1, bReqLinkLimitation = -1,
    bReqDateLimitation = -1; // Date limitation ON/OFF
int nReqSizeLimitation = -1;
int nReqLinkLimitation = -1, bReqLinkDirection = -1, bReqLinkBackward = -1,
    nReqLinkTarget = -2;
int nReqDateLimitation = -1, ReqDateLimitationDateType = -1,
    ReqDateLimitationType = -1;
int nReqKeyDown = -1; // Key input request

// ---------------------------------------------------------------------------
int TDocument::Request(char *Type, int Value, float fValue, void *option) {
  int result = 1;
  UnicodeString T = Type;
  if (T == "Arrange") {
    bReqArrange = Value;
    result = 0;
  } else if (T == "ArrangeMode") {
    nReqArrangeMode = Value;
    result = 0;
  } else if (T == "AutoScroll") {
    bReqAutoScroll = Value;
    result = 0;
  } else if (T == "AutoZoom") {
    bReqAutoZoom = Value;
    result = 0;
  } else if (T == "FullScreen") {
    bReqFullScreen = Value;
    result = 0;
  } else if (T == "Exit") {
    bReqExit = Value;
    result = 0;
  } else if (T == "Zoom") {
    fReqZoom = fValue;
    result = 0;
  } else if (T == "X") {
    fReqX = fValue;
    result = 0;
  } else if (T == "Y") {
    fReqY = fValue;
    result = 0;
  } else if (T == "TargetCard") {
    nReqTargetCard = Value;
    result = 0;
  } else if (T == "DateLimitation") {
    bReqDateLimitation = Value;
    result = 0;
  } else if (T == "LinkLimitation") {
    bReqLinkLimitation = Value;
    result = 0;
  } else if (T == "SizeLimitation") {
    bReqSizeLimitation = Value;
    result = 0;
  } else if (T == "KeyDown") {
    nReqKeyDown = Value;
    result = 0;
  }

  return result; // 0=success
}

// ---------------------------------------------------------------------------
int TDocument::GetCheckCount() {
  // 1=Update, 2=Load, 3=New
  return m_nCheckCount;
}

// ---------------------------------------------------------------------------
int TDocument::GetCardID() {
  // Clipboard target card ID
  return m_nCardID;
}

// ---------------------------------------------------------------------------
int TDocument::CardCount() { return m_Cards->Count; }

// ---------------------------------------------------------------------------
int TDocument::LabelCount(int ltype) { return m_Labels[ltype]->Count; }

// ---------------------------------------------------------------------------
int TDocument::LinkCount() { return m_Links->Count; }

#pragma package(smart_init)
