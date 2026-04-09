// ---------------------------------------------------------------------------
// Core document model implementation split from document.cpp

#pragma hdrstop

#include <math.h>
#include <string.h>

#include "document.h"

int __fastcall Func_CompCardRandom(void *Item1, void *Item2) {
  return (rand() & 2 * 2) - 1;
}

// ---------------------------------------------------------------------------
int __fastcall Func_CompCard(void *Item1, void *Item2) {
  return CompareStr(((TCard *)Item1)->m_Title, ((TCard *)Item2)->m_Title);
}

// ---------------------------------------------------------------------------
int __fastcall Func_CompLabelTouched(void *Item1, void *Item2) {
  float f =
      ((TCardLabel *)Item1)->m_fTouched - ((TCardLabel *)Item2)->m_fTouched;
  if (f > 0.0f) {
    return 1;
  } else if (f == 0.0f) {
    return 0;
  } else {
    return -1;
  }
}

// ---------------------------------------------------------------------------
int __fastcall Func_CompCardCreated(void *Item1, void *Item2) {
  float f = ((TCard *)Item1)->m_fCreated - ((TCard *)Item2)->m_fCreated;
  if (f > 0.0f) {
    return 1;
  } else if (f == 0.0f) {
    return 0;
  } else {
    return -1;
  }
}

// ---------------------------------------------------------------------------
int __fastcall Func_CompCardEdited(void *Item1, void *Item2) {
  float f = ((TCard *)Item1)->m_fUpdated - ((TCard *)Item2)->m_fUpdated;
  if (f > 0.0f) {
    return 1;
  } else if (f == 0.0f) {
    return 0;
  } else {
    return -1;
  }
}

// ---------------------------------------------------------------------------
int __fastcall Func_CompCardViewed(void *Item1, void *Item2) {
  float f = ((TCard *)Item1)->m_fViewed - ((TCard *)Item2)->m_fViewed;
  if (f > 0.0f) {
    return 1;
  } else if (f == 0.0f) {
    return 0;
  } else {
    return -1;
  }
}

// ---------------------------------------------------------------------------
int __fastcall Func_CompCardScore(void *Item1, void *Item2) {
  float f = ((TCard *)Item1)->m_fScore - ((TCard *)Item2)->m_fScore;
  if (f > 0.0f) {
    return 1;
  } else if (f == 0.0f) {
    return 0;
  } else {
    return -1;
  }
}

// ---------------------------------------------------------------------------
int __fastcall Func_CompCardI(void *Item1, void *Item2) {
  return -CompareStr(((TCard *)Item1)->m_Title, ((TCard *)Item2)->m_Title);
}

// ---------------------------------------------------------------------------
int __fastcall Func_CompCardCreatedI(void *Item1, void *Item2) {
  float f = ((TCard *)Item1)->m_fCreated - ((TCard *)Item2)->m_fCreated;
  if (f > 0.0f) {
    return -1;
  } else if (f == 0.0f) {
    return 0;
  } else {
    return 1;
  }
}

// ---------------------------------------------------------------------------
int __fastcall Func_CompCardEditedI(void *Item1, void *Item2) {
  float f = ((TCard *)Item1)->m_fUpdated - ((TCard *)Item2)->m_fUpdated;
  if (f > 0.0f) {
    return -1;
  } else if (f == 0.0f) {
    return 0;
  } else {
    return 1;
  }
}

// ---------------------------------------------------------------------------
int __fastcall Func_CompCardViewedI(void *Item1, void *Item2) {
  float f = ((TCard *)Item1)->m_fViewed - ((TCard *)Item2)->m_fViewed;
  if (f > 0.0f) {
    return -1;
  } else if (f == 0.0f) {
    return 0;
  } else {
    return 1;
  }
}

// ---------------------------------------------------------------------------
int __fastcall Func_CompCardScoreI(void *Item1, void *Item2) {
  float f = ((TCard *)Item1)->m_fScore - ((TCard *)Item2)->m_fScore;
  if (f > 0.0f) {
    return -1;
  } else if (f == 0.0f) {
    return 0;
  } else {
    return 1;
  }
}

// ---------------------------------------------------------------------------
// TDocument
// ---------------------------------------------------------------------------
void TDocument::CreateCardIDToIndex() {
  if (m_CardIDToIndex == NULL) {
    m_CardIDToIndex = new int[m_nMaxCardID];
    for (int i = 0; i < m_nMaxCardID; i++) {
      m_CardIDToIndex[i] = -1;
    }
    for (int i = 0; i < m_Cards->Count; i++) {
      TCard *Card = GetCardByIndex(i);
      m_CardIDToIndex[Card->m_nID] = i;
    }
  }
}

// ---------------------------------------------------------------------------
void TDocument::FreeCardIDToIndex() {
  if (m_CardIDToIndex != NULL) {
    delete[] m_CardIDToIndex;
    m_CardIDToIndex = NULL;
  }
}

// ---------------------------------------------------------------------------
TCard *TDocument::NewCard(int insertindex) {
  CreateCardIDToIndex();
  TCard *Card = new TCard();
  int id = -1;
  for (int i = 0; i < m_nMaxCardID; i++) {
    if (m_CardIDToIndex[i] < 0) {
      id = i;
      break;
    }
  }

  if (id >= 0) {
    Card->m_nID = id;
  } else {
    Card->m_nID = m_nMaxCardID++;
  }
  m_Cards->Insert(insertindex, Card);

  RefreshList();
  return Card;
}

// ---------------------------------------------------------------------------
void TDocument::SortCards(int sorttype, bool inverse) {
  if (!inverse) {
    switch (sorttype) {
    case -1:
      m_Cards->Sort(Func_CompCardRandom);
      break;
    case 0:
      m_Cards->Sort(Func_CompCard);
      break;
    case 1:
      m_Cards->Sort(Func_CompCardCreated);
      break;
    case 2:
      m_Cards->Sort(Func_CompCardEdited);
      break;
    case 3:
      m_Cards->Sort(Func_CompCardViewed);
      break;
    case 4:
      m_Cards->Sort(Func_CompCardScore);
      break;
    }
  } else {
    switch (sorttype) {
    case 0:
      m_Cards->Sort(Func_CompCardI);
      break;
    case 1:
      m_Cards->Sort(Func_CompCardCreatedI);
      break;
    case 2:
      m_Cards->Sort(Func_CompCardEditedI);
      break;
    case 3:
      m_Cards->Sort(Func_CompCardViewedI);
      break;
    case 4:
      m_Cards->Sort(Func_CompCardScoreI);
      break;
    }
  }
  RefreshList();
}

// ---------------------------------------------------------------------------
TCard *TDocument::GetCardByIndex_(int Index) {
  return (TCard *)m_Cards->Items[Index];
}

// ---------------------------------------------------------------------------
TCard *TDocument::GetCardByIndex(int Index) {
  return (TCard *)m_Cards->Items[Index];
}

// ---------------------------------------------------------------------------
void TDocument::SetCardTitle(TCard *Card, UnicodeString string) {
  Card->m_Title = string;
  RefreshList();
}

// ---------------------------------------------------------------------------
void TDocument::SetCardText(TCard *Card, UnicodeString string) {
  Card->m_Lines->Clear();
  Card->m_Lines->Text = string;
  Card->m_fUpdated = Now();
  Card->CheckImageFN();
  m_bChanged = true;
}

// ---------------------------------------------------------------------------
TCard *TDocument::GetCard(int nID) {
  int index = SearchCardIndex(nID);
  if (index >= 0) {
    return GetCardByIndex_(index);
  } else {
    return NULL;
  }
}

// ---------------------------------------------------------------------------
void TDocument::DeleteCard(int nID) {
  int index = SearchCardIndex(nID);
  if (index >= 0) {
    delete (TCard *)m_Cards->Items[index];
    m_Cards->Delete(index);
    RefreshList();
    for (int i = m_Links->Count - 1; i >= 0; i--) {
      TLink *Link = GetLinkByIndex(i);
      if (Link->m_nFromID == nID || Link->m_nDestID == nID) {
        DeleteLinkByIndex(i);
      }
    }
  }
}

// ---------------------------------------------------------------------------
int TDocument::SearchCardIndex(int nID) {
  if (nID >= 0 && nID < m_nMaxCardID) {
    CreateCardIDToIndex();
    return m_CardIDToIndex[nID];
  } else {
    return -1;
  }
}

// ---------------------------------------------------------------------------
void TDocument::ClearCards() {
  while (m_Cards->Count) {
    delete (TCard *)m_Cards->Items[0];
    m_Cards->Delete(0);
  }
  RefreshList();
}

// ---------------------------------------------------------------------------
void TDocument::ClearCardSelection() {
  for (int i = 0; i < m_Cards->Count; i++) {
    TCard *Card = GetCardByIndex(i);
    Card->m_bSelected = false;
  }
}

// ---------------------------------------------------------------------------
void TDocument::SwapCard(int idx1, int idx2) {
  void *bak = m_Cards->Items[idx1];
  m_Cards->Items[idx1] = m_Cards->Items[idx2];
  m_Cards->Items[idx2] = bak;
  RefreshList();
}

// ---------------------------------------------------------------------------
void TDocument::RefreshDateOrder_Label() {
  // Sort by m_fTouchedOrder

  // Label display
  {
    TList *List = new TList();
    for (int il = 0; il < m_Labels[0]->Count; il++) {
      List->Add(GetLabelByIndex(0, il));
    }
    List->Sort(Func_CompLabelTouched);
    for (int i = 0; i < List->Count; i++) {
      ((TCardLabel *)List->Items[i])->m_nTouchedOrder = i;
    }
    delete List;
  }
}

// ---------------------------------------------------------------------------
void TDocument::RefreshDateOrder() {
  // Sort by m_fCreatedOrder
  // Label, card created date display; value 0.0-100.0 for display
  // Used for Date Limitation (date display limit)

  // DateCreated
  {
    TList *List = new TList();
    for (int i = 0; i < m_Cards->Count; i++) {
      List->Add(GetCardByIndex(i));
    }
    List->Sort(Func_CompCardCreated);
    for (int i = 0; i < List->Count; i++) {
      ((TCard *)List->Items[i])->m_nCreatedOrder = i;
    }
    delete List;
  }

  // DateUpdated
  {
    TList *List = new TList();
    for (int i = 0; i < m_Cards->Count; i++) {
      List->Add(GetCardByIndex(i));
    }
    List->Sort(Func_CompCardEdited);
    for (int i = 0; i < List->Count; i++) {
      ((TCard *)List->Items[i])->m_nUpdatedOrder = i;
    }
    delete List;
  }

  // DateViewed
  {
    TList *List = new TList();
    for (int i = 0; i < m_Cards->Count; i++) {
      List->Add(GetCardByIndex(i));
    }
    List->Sort(Func_CompCardViewed);
    for (int i = 0; i < List->Count; i++) {
      ((TCard *)List->Items[i])->m_nViewedOrder = i;
    }
    delete List;
  }
}

// ---------------------------------------------------------------------------
int TDocument::SearchParent(int CardID, bool bChild, bool bFocus) {
  // Parent card loop
  int ParentID = -1;
  double ParentDate = 0.0;
  // Link loop
  for (int il = 0; il < m_Links->Count; il++) {
    TLink *Link = GetLinkByIndex(il);
    if (((Link->m_nDestID == CardID && !bChild) ||
         (Link->m_nFromID == CardID && bChild)) &&
        Link->m_bDirection && Link->m_bVisible) {
      // Card linked to parent (source card)
      TCard *ParentCard;
      if (!bChild) {
        ParentCard = GetCard(Link->m_nFromID);
      } else {
        ParentCard = GetCard(Link->m_nDestID);
      }
      if (ParentCard->m_nID != CardID && ParentCard->m_bVisible &&
          (ParentID == -1 || ParentCard->m_fViewed > ParentDate) &&
          (ParentCard->m_bGetFocus || !bFocus)) {

        // Parent card with most recent view; update parent

        // Update parent card
        ParentID = ParentCard->m_nID;
        ParentDate = ParentCard->m_fViewed;
      }
    }
  }

  return ParentID;
}

// ---------------------------------------------------------------------------
int TDocument::SearchBrother(int CurrentID, int ParentID, bool bInverse,
                             bool bChild, bool bFocus) {
  // Child card loop
  int CardID = -1;
  float MinD = 0.0f;

  // Link loop
  TCard *ParentCard = GetCard(ParentID);
  TCard *CurrentCard = GetCard(CurrentID);
  if (ParentCard && CurrentCard) {
    float xd0 = ParentCard->m_fX - CurrentCard->m_fX;
    float yd0 = ParentCard->m_fY - CurrentCard->m_fY;
    float rad0 = 0.0f;
    if (xd0 != 0.0f || yd0 != 0.0f) {
      rad0 = atan2(yd0, xd0);
    }

    for (int il = 0; il < m_Links->Count; il++) {
      TLink *Link = GetLinkByIndex(il);
      if (((Link->m_nDestID == ParentID && bChild) ||
           (Link->m_nFromID == ParentID && !bChild)) &&
          Link->m_bDirection && Link->m_bVisible) {
        // Card linked to parent (child)
        TCard *Card;
        if (bChild) {
          Card = GetCard(Link->m_nFromID);
        } else {
          Card = GetCard(Link->m_nDestID);
        }
        if (Card->m_bVisible && Card->m_nID != CurrentID &&
            (Card->m_bGetFocus || !bFocus)) {
          // Angle calculation
          float xd = ParentCard->m_fX - Card->m_fX;
          float yd = ParentCard->m_fY - Card->m_fY;
          float rad = 0.0f;
          if (xd != 0.0f || yd != 0.0f) {
            rad = atan2(yd, xd);
          }
          rad = rad0 - rad;
          while (rad < 0.0f) {
            rad += 2 * M_PI;
          }

          if (CardID == -1 || ((MinD < rad) == bInverse)) {
            // Closest card

            // Update card
            CardID = Card->m_nID;
            MinD = rad;
          }
        }
      }
    }
  }

  return CardID;
}

// ---------------------------------------------------------------------------
int TDocument::SearchLast(int CardID, bool bFocus) {
  // External link display card loop
  // Parent card loop
  int LastID = -1;
  double LastDate = 0.0;
  // Card loop
  for (int i = 0; i < m_Cards->Count; i++) {
    TCard *Card = GetCardByIndex(i);
    if (Card->m_bVisible && Card->m_nID != CardID &&
        (LastID == -1 || Card->m_fViewed > LastDate) &&
        (Card->m_bGetFocus || !bFocus)) {
      // Card with most recent view; update card

      // Update card
      LastID = Card->m_nID;
      LastDate = Card->m_fViewed;
    }
  }

  return LastID;
}

// ---------------------------------------------------------------------------
void TDocument::RefreshCardLevel() {
  // Card->m_bTop order hierarchy; card display

  // Target backup
  void **orderbak = new void *[m_Cards->Count];
  for (int i = 0; i < m_Cards->Count; i++) {
    TCard *Card = GetCardByIndex(i);
    orderbak[i] = Card;
    Card->m_nLevel = 0;
    Card->m_nParentID = -1; // Use parent card ID
    Card->m_bHasChild = false;
  }

  TList *RCard = GetRelatedCard(true, true); // Cards linked to target card

  // Target loop
  bool changed = true;
  int level = 1;
  while (changed) {
    changed = false;
    // Card loop
    for (int i = 0; i < m_Cards->Count; i++) {
      TCard *Card = GetCardByIndex(i);
      if (!Card->m_bTop && Card->m_nLevel == 0 && Card->m_nParentID == -1) {
        // Target card
        // Count cards linked to target
        int count = RelatedCardNum(RCard, i);
        if (count) {
          // Cards linked to target

          // Find parent card from linked cards
          int startindex = 0;
          for (int il = 0; il < count; il++) {
            int index = RelatedIndex(RCard, i, il);
            if (index < i) {
              // Card before index
              startindex = il;
            } else {
              break;
            }
          }

          // Target
          bool changed1 = false;
          int il = startindex;
          int count2 = count;
          do {
            int index = RelatedIndex(RCard, i, il);
            TCard *Card2 = GetCardByIndex(index);

            if (i != index &&
                (Card2->m_bTop ||
                 (Card2->m_nLevel > 0 && Card2->m_nLevel == level - 1))) {
              // Parent card found

              // Parent card get
              Card->m_nLevel = level;
              Card->m_nParentID = Card2->m_nID;
              Card2->m_bHasChild = true;
              changed1 = true;
              break;
            }

            il = (il + count - 1) % count; // One before
            count2--;
          } while (count2); // Sort loop complete

          changed |= changed1;
        }
      }
    }
    level++;
  }
  int maxlevel = level;

  FreeRelatedCard(RCard);

  // Card order
  FreeCardIDToIndex();

  // Top card order
  for (int i = 1; i < m_Cards->Count; i++) {
    TCard *Card = GetCardByIndex(i);
    if (Card->m_bTop) {
      int index = i;
      while (index > 0) {
        TCard *Card2 = GetCardByIndex(index - 1); // Previous card
        if (!Card2->m_bTop) {
          m_Cards->Items[index - 1] = Card;
          m_Cards->Items[index] = Card2;
          index--;
        } else {
          break;
        }
      }
    }
  }

  // Target loop
  level = 0;
  int moved = true;
  while (moved || level <= maxlevel) {
    moved = false;
    // Parent card loop
    // Card loop
    for (int i = 0; i < m_Cards->Count; i++) {
      TCard *Card = GetCardByIndex(i);
      if ((Card->m_bTop && level == 0) ||
          (Card->m_nLevel == level && Card->m_nLevel > 0)) {
        // Parent card
        int insindex = i + 1; // Insert between parent and child card

        // Card loop (child)
        for (int i2 = 0; i2 < m_Cards->Count; i2++) {
          TCard *Card2 = GetCardByIndex(i2);
          if (Card2->m_nParentID == Card->m_nID) {
            // Parent card child
            if (i2 < insindex) {
              // Before insert position
              // No move needed
            } else if (i2 > insindex) {
              // Move cards insindex<=x<i2 by 1
              for (int i3 = i2; i3 > insindex; i3--) {
                m_Cards->Items[i3] = m_Cards->Items[i3 - 1];
              }
              m_Cards->Items[insindex] = Card2;
              insindex++;
              moved = true;
              i2--;
              i++;
            } else {
              // Already at insert position
              insindex++;
            }
          }
        }
      }
    }

    level++;
  }

  // Index check
  changed = false;
  for (int i = 0; i < m_Cards->Count && !changed; i++) {
    changed |= orderbak[i] != m_Cards->Items[i];
  }
  if (changed) {
    RefreshList();
  }

  delete[] orderbak;
}

// ---------------------------------------------------------------------------
void TDocument::AddLabelToCard(TCard *Card, int label) {
  Card->m_Labels->AddLabel(label);
}

// ---------------------------------------------------------------------------
void TDocument::DeleteLabelFromCard(TCard *Card, int label) {
  Card->m_Labels->DeleteLabel(label);
}

// ---------------------------------------------------------------------------
TList *TDocument::GetRelatedCard(bool bInverse, bool bVisibleOnly) {
  // RCard: parent card linked to target card index
  TList *RCard = new TList();
  if (m_Cards->Count) {
    for (int i = 0; i < m_Cards->Count; i++) {
      RCard->Add(new TList());
    }

    bool *matrix = new bool[m_Cards->Count * m_Cards->Count];
    memset(matrix, 0, sizeof(bool) * m_Cards->Count * m_Cards->Count);

    for (int il = 0; il < m_Links->Count; il++) {
      TLink *Link = GetLinkByIndex(il);
      if ((Link->m_bVisible || !bVisibleOnly) && Link->m_bDirection) {
        int indexfrom = SearchCardIndex(Link->m_nFromID);
        TCard *From = GetCardByIndex(indexfrom);
        int indexdest = SearchCardIndex(Link->m_nDestID);
        TCard *Dest = GetCardByIndex(indexdest);
        if ((From->m_bVisible && Dest->m_bVisible) || !bVisibleOnly) {
          if (bInverse) {
            // Reverse (parent card linked to target card index)
            matrix[indexdest * m_Cards->Count + indexfrom] = true;
          } else {
            // Forward
            matrix[indexfrom * m_Cards->Count + indexdest] = true;
          }
        }
      }
    }

    for (int ifrom = 0; ifrom < m_Cards->Count; ifrom++) {
      for (int idest = 0; idest < m_Cards->Count; idest++) {
        if (matrix[ifrom * m_Cards->Count + idest]) {
          ((TList *)RCard->Items[ifrom])->Add((void *)(intptr_t)idest);
        }
      }
    }
    delete[] matrix;
  }
  return RCard;
}

// ---------------------------------------------------------------------------
int TDocument::RelatedCardNum(TList *RCard, int cardindex) {
  return ((TList *)RCard->Items[cardindex])->Count;
}

// ---------------------------------------------------------------------------
int TDocument::RelatedIndex(TList *RCard, int cardindex, int index) {
  return (int)((TList *)RCard->Items[cardindex])->Items[index];
}

// ---------------------------------------------------------------------------
void TDocument::FreeRelatedCard(TList *RCard) {
  // Free RCard
  for (int i = 0; i < m_Cards->Count; i++) {
    delete (TList *)RCard->Items[i];
  }
  delete RCard;
}

// ---------------------------------------------------------------------------
TDocument::TDocument() { InitDocument(); }

// ---------------------------------------------------------------------------
void TDocument::InitDocument() {
  m_nRefreshListCount = 0;
  m_nRefreshLinkCount = 0;
  m_nRefreshLabelCount = 0;

  m_nMaxCardID = 0;
  m_CardIDToIndex = NULL;
  m_nCardID = -1;
  m_FN = "";

  m_Cards = new TList();
  TCard *Card = new TCard();
  Card->m_fX = 0.5;
  Card->m_fY = 0.5;
  m_Cards->Add(Card);
  m_nMaxCardID++;
  RefreshList();

  m_Links = new TList();
  RefreshLink();

  m_Labels[0] = new TList();
  InitLabel(0);

  m_Labels[1] = new TList();
  InitLabel(1);

  RefreshLabel();

  m_bChanged = false;
  m_bReadOnly = false;
  m_nDefaultView = -1;

  m_nAutoSave = 0;
  m_nAutoReload = 0;

  m_nCheckCount = 0;
}

// ---------------------------------------------------------------------------
TDocument::TDocument(TDocument &Doc) {
  // Save
  InitDocument();

  CopyFrom(&Doc);
}

// ---------------------------------------------------------------------------
void TDocument::CopyFrom(TDocument *Doc) {
  ClearCards();
  ClearLinks();
  ClearLabels(0);
  ClearLabels(1);

  // Card load
  for (int i = 0; i < Doc->m_Cards->Count; i++) {
    TCard *Card = Doc->GetCardByIndex(i);
    m_Cards->Add(new TCard(*Card));
    if (Card->m_nID >= m_nMaxCardID) {
      m_nMaxCardID = Card->m_nID + 1;
    }
  }

  // Link load
  for (int i = 0; i < Doc->m_Links->Count; i++) {
    m_Links->Add(new TLink(*Doc->GetLinkByIndex(i)));
  }

  // Label load
  for (int il = 0; il < 2; il++) {
    for (int i = 0; i < Doc->m_Labels[il]->Count; i++) {
      m_Labels[il]->Add(new TCardLabel(*Doc->GetLabelByIndex(il, i)));
    }
  }

  // Update type
  m_nCheckCount = Doc->m_nCheckCount;
  // Load update
  m_nRefreshListCount = Doc->m_nRefreshListCount;
  m_nRefreshLinkCount = Doc->m_nRefreshLinkCount;
  m_nRefreshLabelCount = Doc->m_nRefreshLabelCount;

  // Init
  m_bChanged = Doc->m_bChanged;
  m_FN = Doc->m_FN;
  m_bReadOnly = Doc->m_bReadOnly;

  m_nCardID = Doc->m_nCardID; // Focus card (for display)
  m_nDefaultView = Doc->m_nDefaultView;
  // Display mode (-1=none, 0=Browser, 1=Editor)
}

// ---------------------------------------------------------------------------
TDocument::~TDocument() {
  FreeCardIDToIndex();

  ClearLabels(1);
  ClearLabels(0);
  delete m_Labels[1];
  delete m_Labels[0];

  ClearLinks();
  delete m_Links;
  ClearCards();
  delete m_Cards;
}

// ---------------------------------------------------------------------------
void TDocument::RefreshList() {
  FreeCardIDToIndex();

  m_nRefreshListCount++;
  m_bChanged = true;
}

// ---------------------------------------------------------------------------
void TDocument::ClearLinks() {
  for (int i = 0; i < m_Links->Count; i++) {
    delete GetLinkByIndex(i);
  }
  m_Links->Clear();
}

// ---------------------------------------------------------------------------
void TDocument::AddLabelToLink(TLink *Link, int label) {
  Link->m_Labels->AddLabel(label);
}

// ---------------------------------------------------------------------------
void TDocument::DeleteLabelFromLink(TLink *Link, int label) {
  Link->m_Labels->DeleteLabel(label);
}

// ---------------------------------------------------------------------------
TLink *TDocument::GetLinkByIndex(int index) {
  if (index >= 0 && index < m_Links->Count) {
    return (TLink *)(m_Links->Items[index]);
  }
  return NULL;
}

// ---------------------------------------------------------------------------
void TDocument::SetLinkName(TLink *Link, UnicodeString S) { Link->m_Name = S; }

// ---------------------------------------------------------------------------
void TDocument::DeleteLinkByIndex(int index) {
  delete GetLinkByIndex(index);
  m_Links->Delete(index);
  m_nRefreshLinkCount++;
  m_bChanged = true;
}

// ---------------------------------------------------------------------------
void TDocument::RefreshLink() {
  m_nRefreshLinkCount++;
  m_bChanged = true;
}

// ---------------------------------------------------------------------------
TLink *TDocument::NewLink() {
  TLink *Link = new TLink();
  m_Links->Add(Link);
  RefreshLink();
  return Link;
}

// ---------------------------------------------------------------------------
void TDocument::InitLabel(int ltype) {
  ClearLabels(ltype);

  if (ltype == 0) {
    for (int i = 0; i < 3; i++) {
      NewLabel(ltype);
    }

    GetLabelByIndex(0, 0)->m_Name = "Problem";
    GetLabelByIndex(0, 0)->m_nColor = 0xff0000;

    GetLabelByIndex(0, 1)->m_Name = "Solution";
    GetLabelByIndex(0, 1)->m_nColor = 0x00ff00;

    GetLabelByIndex(0, 2)->m_Name = "Result";
    GetLabelByIndex(0, 2)->m_nColor = 0x0000ff;
  }
}

// ---------------------------------------------------------------------------
void TDocument::ClearLabels(int ltype) {
  for (int i = 0; i < m_Labels[ltype]->Count; i++) {
    delete GetLabelByIndex(ltype, i);
  }
  m_Labels[ltype]->Clear();
}

// ---------------------------------------------------------------------------
bool TDocument::LabelIsFold(TCard *Card) {
  // Label loop
  bool fold = CountEnableLabel(Card) > 0;
  for (int il = 0; il < Card->m_Labels->Count && fold; il++) {
    TCardLabel *Label = GetLabelByIndex(0, Card->m_Labels->GetLabel(il) - 1);
    if (Label->m_bEnable) {
      fold &= Label->m_bFold;
    }
  }

  return fold;
}

// ---------------------------------------------------------------------------
int TDocument::CountEnableLabel(TCard *Card) {
  // Card link limitation

  // Label loop
  int count = 0;
  for (int il = 0; il < Card->m_Labels->Count; il++) {
    TCardLabel *Label = GetLabelByIndex(0, Card->m_Labels->GetLabel(il) - 1);
    count += Label->m_bEnable;
  }

  return count;
}

// ---------------------------------------------------------------------------
bool TDocument::LabelIsSame(TCard *Card1, TCard *Card2) {
  // 2 cards limitation

  if (CountEnableLabel(Card1) != CountEnableLabel(Card2)) {
    return false;
  }
  for (int i = 0; i < Card1->m_Labels->Count; i++) {
    int labelindex = Card1->m_Labels->GetLabel(i);
    TCardLabel *Label = GetLabelByIndex(0, labelindex - 1);
    if (Label->m_bEnable) {
      if (!Card2->m_Labels->Contain(labelindex)) {
        return false;
      }
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
TCardLabel *TDocument::GetLabel(int ltype, UnicodeString S) {
  for (int i = 0; i < m_Labels[ltype]->Count; i++) {
    TCardLabel *Label = GetLabelByIndex(ltype, i);
    if (Label->m_Name == S) {
      return Label;
    }
  }
  return NULL;
}

// ---------------------------------------------------------------------------
TCardLabel *TDocument::GetLabelByIndex(int ltype, int index) {
  return (TCardLabel *)(m_Labels[ltype]->Items[index]);
}

// ---------------------------------------------------------------------------
void TDocument::SetLabelName(TCardLabel *Label, UnicodeString S) {
  Label->m_Name = S;
}

// ---------------------------------------------------------------------------
void TDocument::DeleteLabelByIndex(int ltype, int index) {
  if (ltype == 0) {
    // Card limitation
    for (int i = 0; i < m_Cards->Count; i++) {
      TCard *Card = GetCardByIndex_(i);

      for (int il = 0; il < Card->m_Labels->Count; il++) {
        if (Card->m_Labels->GetLabel(il) > index + 1) {
          // Label limitation index check
          Card->m_Labels->SetLabel(il, Card->m_Labels->GetLabel(il) - 1);
        } else if (Card->m_Labels->GetLabel(il) == index + 1) {
          // Label limitation card link check
          Card->m_Labels->DeleteLabel(index + 1);
          il--;
        }
      }
    }
  } else {
    // Link limitation
    for (int i = 0; i < m_Links->Count; i++) {
      TLink *Link = GetLinkByIndex(i);

      for (int il = 0; il < Link->m_Labels->Count; il++) {
        if (Link->m_Labels->GetLabel(il) > index + 1) {
          // Label limitation index check
          Link->m_Labels->SetLabel(il, Link->m_Labels->GetLabel(il) - 1);
        } else if (Link->m_Labels->GetLabel(il) == index + 1) {
          // Label limitation card link check
          Link->m_Labels->DeleteLabel(index + 1);
          il--;
        }
      }
    }
  }

  delete GetLabelByIndex(ltype, index);
  m_Labels[ltype]->Delete(index);
  m_nRefreshLabelCount++;
  m_bChanged = true;
}

// ---------------------------------------------------------------------------
void TDocument::RefreshLabel() {
  m_nRefreshLabelCount++;
  m_bChanged = true;
}

// ---------------------------------------------------------------------------
TCardLabel *TDocument::NewLabel(int ltype) {
  TCardLabel *Label = new TCardLabel();
  m_Labels[ltype]->Add(Label);
  RefreshLabel();
  return Label;
}

#pragma package(smart_init)
