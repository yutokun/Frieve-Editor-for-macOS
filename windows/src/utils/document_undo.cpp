// ---------------------------------------------------------------------------
// Undo/redo implementation split from document.cpp

#pragma hdrstop

#include "document.h"

// TUndoRedo
// ---------------------------------------------------------------------------
TUndoRedoData::TUndoRedoData(TDocument *Doc, UnicodeString Name, int CardID,
                             int SelStart, int SelLength)
    : m_Doc(new TDocument(*Doc)), m_Name(Name), m_nCardID(CardID),
      m_nSelStart(SelStart), m_nSelLength(SelLength) {}

// ---------------------------------------------------------------------------
TUndoRedoData::~TUndoRedoData() { delete m_Doc; }

// ---------------------------------------------------------------------------
inline TUndoRedoData *TUndoRedo::UndoData(int index) {
  return (TUndoRedoData *)m_Undos->Items[index];
}

// ---------------------------------------------------------------------------
inline TUndoRedoData *TUndoRedo::RedoData(int index) {
  return (TUndoRedoData *)m_Redos->Items[index];
}

// ---------------------------------------------------------------------------
TUndoRedo::TUndoRedo(int maxundo)
    : m_Undos(new TList()), m_Redos(new TList()), m_nMaxUndo(maxundo),
      m_bChanged(false) {}

// ---------------------------------------------------------------------------
TUndoRedo::~TUndoRedo() {
  ClearRedos();
  ClearUndos();
  delete m_Redos;
  delete m_Undos;
}

// ---------------------------------------------------------------------------
void TUndoRedo::ClearUndos() {
  for (int i = 0; i < m_Undos->Count; i++) {
    delete UndoData(i);
  }
  m_Undos->Clear();
}

// ---------------------------------------------------------------------------
void TUndoRedo::ClearRedos() {
  for (int i = 0; i < m_Redos->Count; i++) {
    delete RedoData(i);
  }
  m_Redos->Clear();
}

// ---------------------------------------------------------------------------
void TUndoRedo::Backup(TDocument *Doc, UnicodeString editname, int CardID,
                       int SelStart, int SelLength) {
  ClearRedos();
  m_Undos->Insert(
      0, new TUndoRedoData(Doc, editname, CardID, SelStart, SelLength));
  while (m_Undos->Count > m_nMaxUndo) {
    delete UndoData(m_Undos->Count - 1);
    m_Undos->Delete(m_Undos->Count - 1);
  }
}

// ---------------------------------------------------------------------------
void TUndoRedo::Undo(TDocument *Doc, int CardID, int SelStart, int SelLength,
                     int *NextCardID, int *NextSelStart, int *NextSelLength) {
  TUndoRedoData *Data = UndoData(0);
  UnicodeString UndoName = Data->m_Name;
  *NextCardID = Data->m_nCardID;
  *NextSelStart = Data->m_nSelStart;
  *NextSelLength = Data->m_nSelLength;

  // Redo current data
  m_Redos->Insert(
      0, new TUndoRedoData(Doc, UndoName, CardID, SelStart, SelLength));

  // Undo
  Doc->CopyFrom(Data->m_Doc);

  // Undo back
  delete Data;
  m_Undos->Delete(0);

  m_bChanged = true;
}

// ---------------------------------------------------------------------------
void TUndoRedo::Redo(TDocument *Doc, int CardID, int SelStart, int SelLength,
                     int *NextCardID, int *NextSelStart, int *NextSelLength) {
  TUndoRedoData *Data = RedoData(0);
  UnicodeString RedoName = Data->m_Name;
  *NextCardID = Data->m_nCardID;
  *NextSelStart = Data->m_nSelStart;
  *NextSelLength = Data->m_nSelLength;

  // Undo current data
  m_Undos->Insert(
      0, new TUndoRedoData(Doc, RedoName, CardID, SelStart, SelLength));

  // Redo
  Doc->CopyFrom(Data->m_Doc);

  // Redo back
  delete Data;
  m_Redos->Delete(0);

  m_bChanged = true;
}

// ---------------------------------------------------------------------------
bool TUndoRedo::GetCanUndo(UnicodeString &editname) {
  if (m_Undos->Count) {
    editname = UndoData(0)->m_Name;
    return true;
  } else {
    editname = "";
    return false;
  }
}

// ---------------------------------------------------------------------------
bool TUndoRedo::GetCanRedo(UnicodeString &editname) {
  if (m_Redos->Count) {
    editname = RedoData(0)->m_Name;
    return true;
  } else {
    editname = "";
    return false;
  }
}
// ---------------------------------------------------------------------------

#pragma package(smart_init)
