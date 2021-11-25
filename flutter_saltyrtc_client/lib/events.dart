/// Contains all events raised by the SlatyRtc client.
///
/// Tasks can define additional events based on either:
///
/// - [Event]
/// - [ClosingErrorEvent] (which will cause an exception)
library flutter_saltyrtc_client.events;

import 'package:xayn_saltyrtc_client/events.dart' show Event, ClosingErrorEvent;

//Re-export all events.
export 'package:xayn_saltyrtc_client/events.dart';
