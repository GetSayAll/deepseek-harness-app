# DS Harness macOS 0.1.1 Design QA

## Comparison target

- Source visual truth: `output/imagegen/deepseek-harness-macos-empty-state-v1.png`, `output/imagegen/deepseek-harness-macos-active-conversation-v1.png`, `output/imagegen/deepseek-harness-macos-tool-details-v1.png`, `output/imagegen/deepseek-harness-macos-approval-v1.png`, `output/imagegen/deepseek-harness-macos-question-v1.png`, and `output/imagegen/deepseek-harness-macos-settings-v1.png`.
- Written precedence: `apps/macos/DESIGN.md`.
- Implementation: the packaged `apps/macos/dist/DS Harness.app`, version `0.1.1 (1)`, running its bundled Node runtime and native Host.
- Viewports: the main window at its `1280 × 800 pt` default and `900 × 600 pt` minimum, plus the `920 × 700 pt` settings window.
- States: empty conversation, active conversation, selected tool details, approval waiting and rejection, structured-question waiting and selection, and model settings.

## Comparison evidence

The packaged application was opened and captured through macOS accessibility and window screenshots. Each required state was compared beside its V1 reference at original image density, with `apps/macos/DESIGN.md` taking precedence over generated example content.

The default-size main window preserves the V1 light three-column hierarchy. The expanded sidebar uses the light blue-gray fill, the conversation uses the low-interference base background, and selected tools open the independent right detail column. The input JSON card remains light and terminal output remains dark.

The empty state places the brand mark, task heading, guidance, workspace action, and Composer on one central axis. With no configured workspace, the Composer reads `选择一个工作区开始`, disables text entry and sending, and keeps the workspace action available. At `900 × 600 pt`, the sidebar becomes the `56 pt` icon rail, the detail column stays absent, and the empty-state content remains visible without clipping.

Approval and structured questions replace the Composer seat without changing the conversation axis. The approval card uses the warning treatment, shows the reason and tool arguments, and orders `拒绝` before the primary `允许一次` action. Rejecting the QA escalation restored the Composer and did not create the requested file outside the workspace. The question card exposed native single-choice semantics, optional detail, skip, disabled submission until answered, selected-state feedback, and successful return to the normal Composer.

The settings window matches the V1 navigation and provider-card hierarchy. It shows the DeepSeek credential as configured without revealing the value, exposes the Base URL, states that Node and Host are bundled, and reports the Host connection in the footer. Default-model and model-catalog controls remain absent because the native protocol does not supply reliable values for them.

## Findings and resolutions

- [Resolved P1] A newly created blank session bypassed the empty-state hero because the view tested only for a missing session identifier. `ConversationView` now treats an idle session with no conversation or pending interaction as the empty state.
- [Resolved P1] A blank session without a configured workspace exposed an editable Composer. `ComposerView` now requires a workspace before enabling composition, regardless of whether a blank session identifier exists.
- [Resolved P1] `⌘N` and `⌘⇧O` were attached only to controls in the expanded sidebar, so compact mode removed their shortcut handlers. The application File commands now own both shortcuts while sidebar controls retain their click behavior.
- No open P0, P1, or P2 visual findings remain in the required `0.1.1` states.

## Functional evidence attached to visual states

- The packaged Host completed a cold connection and restored persisted sessions.
- A real DeepSeek turn invoked `ask_user_question`; option selection, submission, and the model continuation completed.
- A real bash request outside the workspace produced the approval card; rejection completed and the target file remained absent.
- A completed bash tool rendered its input JSON and terminal output in the right detail column.
- Closing Settings and reopening or creating a main window restored a visible main window rather than leaving only a secondary window.
- Native menu routing handled copy, cut, paste, undo, hide, and quit. `⌘N` created a blank session and `⌘⇧O` opened the directory picker at the minimum window size; Escape canceled the picker.

final result: passed
