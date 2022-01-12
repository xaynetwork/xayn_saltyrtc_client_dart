// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
