// ---------------------------------------------------------------------------
// Document clipboard implementation split from document.cpp

#pragma hdrstop

#include <clipbrd.hpp>
#include <math.h>
#include <string.h>

#include "document.h"

// ---------------------------------------------------------------------------
void TDocument::CopyToClipboard() {
  // Load file path
  TDocument *D2 = new TDocument(*this);

  // Select card (yes) or card not selected (no)
  for (int i = D2->m_Cards->Count - 1; i >= 0; i--) {
    TCard *Card = D2->GetCardByIndex(i);
    if (!Card->m_bSelected) {
      D2->DeleteCard(Card->m_nID);
    }
  }

  // Used card limitation
  // Used limitation
  bool *LabelUsed;
  LabelUsed = new bool[D2->m_Labels[0]->Count];
  memset(LabelUsed, 0, sizeof(bool) * D2->m_Labels[0]->Count);
  for (int i = 0; i < D2->m_Cards->Count; i++) {
    TCard *Card = D2->GetCardByIndex(i);
    for (int il = 0; il < Card->m_Labels->Count; il++) {
      LabelUsed[Card->m_Labels->GetLabel(il) - 1] = true;
    }
  }
  // Used link limitation
  for (int il = D2->m_Labels[0]->Count - 1; il >= 0; il--) {
    if (!LabelUsed[il]) {
      D2->DeleteLabelByIndex(0, il);
    }
  }
  delete[] LabelUsed;

  // Used link limitation
  // Used date limitation
  LabelUsed = new bool[D2->m_Labels[1]->Count];
  memset(LabelUsed, 0, sizeof(bool) * D2->m_Labels[1]->Count);
  for (int i = 0; i < D2->m_Links->Count; i++) {
    TLink *Link = D2->GetLinkByIndex(i);
    for (int il = 0; il < Link->m_Labels->Count; il++) {
      LabelUsed[Link->m_Labels->GetLabel(il) - 1] = true;
    }
  }
  // Used link limitation
  for (int il = D2->m_Labels[1]->Count - 1; il >= 0; il--) {
    if (!LabelUsed[il]) {
      D2->DeleteLabelByIndex(1, il);
    }
  }
  delete[] LabelUsed;

  // Clipboard load
  TStringList *SL = new TStringList();
  D2->SaveToString(SL);
  Clipboard()->SetTextBuf(SL->Text.c_str());
  delete SL;

  delete D2;
}

// ---------------------------------------------------------------------------
void TDocument::PasteFromClipboard(float fSpan) {
  if (!Clipboard()->HasFormat(CF_TEXT)) {
    return;
  }
  TStringList *SL = new TStringList();
  SL->Text = Clipboard()->AsText;
  TDocument *D2 = new TDocument();
  D2->LoadFromString(SL, "");

  // Label check
  int *labelassign[2];
  for (int lt = 0; lt < 2; lt++) {
    labelassign[lt] = new int[D2->m_Labels[lt]->Count];
    for (int il = 0; il < D2->m_Labels[lt]->Count; il++) {
      TCardLabel *Label = D2->GetLabelByIndex(lt, il);
      bool found = false;
      for (int il2 = 0; il2 < m_Labels[lt]->Count && !found; il2++) {
        TCardLabel *Label2 = GetLabelByIndex(lt, il2);

        if (Label->m_Name == Label2->m_Name) {
          labelassign[lt][il] = il2;
          found = true;
        }
      }
      if (!found) {
        m_Labels[lt]->Add(new TCardLabel(*Label));
        labelassign[lt][il] = m_Labels[lt]->Count - 1;
      }
    }
  }

  // Card ID update
  int *cardassign = new int[D2->m_nMaxCardID];
  for (int ic = 0; ic < D2->m_Cards->Count; ic++) {
    TCard *Card = new TCard(*D2->GetCardByIndex(ic));

    cardassign[Card->m_nID] = m_nMaxCardID;
    Card->m_nID = m_nMaxCardID++;

    // Label undo
    for (int il = 0; il < Card->m_Labels->Count; il++) {
      Card->m_Labels->SetLabel(
          il, labelassign[0][Card->m_Labels->GetLabel(il) - 1] + 1);
    }

    for (int ic2 = 0; ic2 < m_Cards->Count; ic2++) {
      TCard *Card2 = GetCardByIndex(ic2);
      if (fabs(Card2->m_fX - Card->m_fX) < 0.0000001f &&
          fabs(Card2->m_fY - Card->m_fY) < 0.0000001f) {
        Card->m_fX += fSpan;
        Card->m_fY += fSpan;
        ic2 = -1;
      }
    }

    m_Cards->Add(Card);
  }

  // Link
  for (int il = 0; il < D2->m_Links->Count; il++) {
    TLink *Link = new TLink(*D2->GetLinkByIndex(il));
    Link->m_nFromID = cardassign[Link->m_nFromID];
    Link->m_nDestID = cardassign[Link->m_nDestID];

    // Label undo
    for (int il = 0; il < Link->m_Labels->Count; il++) {
      Link->m_Labels->SetLabel(
          il, labelassign[1][Link->m_Labels->GetLabel(il) - 1] + 1);
    }

    m_Links->Add(Link);
  }

  // End
  delete[] cardassign;
  for (int lt = 0; lt < 2; lt++) {
    delete[] labelassign[lt];
  }

  delete D2;
  delete SL;

  RefreshList();
  RefreshLink();
  RefreshLabel();
}

#pragma package(smart_init)
