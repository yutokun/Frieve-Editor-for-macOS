// ---------------------------------------------------------------------------
#ifndef fomain_timer_opsH
#define fomain_timer_opsH
// ---------------------------------------------------------------------------

class TObject;
class TFo_Main;

namespace FomainTimerOps {
void HandleContinuousLoad(TFo_Main *mainForm);
void HandleAutoReload(TFo_Main *mainForm, unsigned int tick);
void HandleAutoSave(TFo_Main *mainForm, unsigned int tick);
void HandlePluginTimeout(TFo_Main *mainForm);
void ApplyDefaultView(TFo_Main *mainForm);
bool ApplyOperationRequests(TFo_Main *mainForm, TObject *Sender);
void UpdateWindowTitles(TFo_Main *mainForm);
void UpdateFileListPanel(TFo_Main *mainForm);
} // namespace FomainTimerOps

// ---------------------------------------------------------------------------
#endif
