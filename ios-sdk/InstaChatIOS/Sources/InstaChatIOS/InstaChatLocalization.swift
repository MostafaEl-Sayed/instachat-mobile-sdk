import Foundation

/// Language used by InstaChat's interface. Pass a value from the host app to
/// keep chat in sync with the app. When omitted, the SDK follows the device's
/// preferred language.
public enum InstaChatLanguage: String, Codable, Hashable, Sendable {
  case english = "en"
  case arabic = "ar"

  public init(identifier: String) {
    self = identifier.lowercased().hasPrefix("ar") ? .arabic : .english
  }

  public static var devicePreferred: InstaChatLanguage {
    InstaChatLanguage(identifier: Locale.preferredLanguages.first ?? "en")
  }

  public var locale: Locale {
    Locale(identifier: rawValue)
  }

  public var isRightToLeft: Bool {
    self == .arabic
  }
}

struct InstaChatLocalizer: Sendable {
  let language: InstaChatLanguage

  func text(_ english: String) -> String {
    guard language == .arabic else { return english }
    return Self.arabic[english] ?? english
  }

  func format(_ englishFormat: String, _ arguments: CVarArg...) -> String {
    String(format: text(englishFormat), locale: language.locale, arguments: arguments)
  }

  private static let arabic: [String: String] = [
    "Messages": "الرسائل",
    "Chat": "المحادثة",
    "Online": "متصل الآن",
    "Message": "رسالة",
    "Loading chats": "جارٍ تحميل المحادثات",
    "No Chats": "لا توجد محادثات",
    "New conversations will appear here.": "ستظهر المحادثات الجديدة هنا.",
    "Unable to Load Chats": "تعذر تحميل المحادثات",
    "Unable to Complete Action": "تعذر إكمال الإجراء",
    "Please try again.": "يرجى المحاولة مرة أخرى.",
    "OK": "حسنًا",
    "Close chat": "إغلاق المحادثة",
    "Tap to open conversation": "اضغط لفتح المحادثة",
    "Unread messages": "رسائل غير مقروءة",
    "Open provider profile": "فتح ملف مقدم الخدمة",
    "Open attachments": "فتح المرفقات",
    "Record voice note": "تسجيل رسالة صوتية",
    "Cancel voice note": "إلغاء الرسالة الصوتية",
    "Send voice note": "إرسال الرسالة الصوتية",
    "Location": "الموقع",
    "Photo": "صورة",
    "Video": "فيديو",
    "Voice note": "رسالة صوتية",
    "File": "ملف",
    "Share a location": "مشاركة موقع",
    "Choose photos": "اختيار صور",
    "Choose a video": "اختيار فيديو",
    "Sending": "جارٍ الإرسال",
    "Retry": "إعادة المحاولة",
    "Retry sending message": "إعادة محاولة إرسال الرسالة",
    "Copy": "نسخ",
    "Copy message": "نسخ الرسالة",
    "Tap to preview": "اضغط للمعاينة",
    "Play video %@": "تشغيل الفيديو %@",
    "Open image %@": "فتح الصورة %@",
    "Open image": "فتح الصورة",
    "Downloading voice note": "جارٍ تنزيل الرسالة الصوتية",
    "Pause voice note": "إيقاف الرسالة الصوتية مؤقتًا",
    "Retry voice note": "إعادة محاولة تشغيل الرسالة الصوتية",
    "Play voice note": "تشغيل الرسالة الصوتية",
    "Download voice note": "تنزيل الرسالة الصوتية",
    "Voice note isn't ready yet.": "الرسالة الصوتية غير جاهزة بعد.",
    "Retry voice note playback": "إعادة محاولة تشغيل الرسالة الصوتية",
    "Could not play audio": "تعذر تشغيل الصوت",
    "Voice note playback failed": "فشل تشغيل الرسالة الصوتية",
    "Close preview": "إغلاق المعاينة",
    "Attempts to load this image again": "يحاول تحميل الصورة مرة أخرى",
    "Preparing video...": "جارٍ تجهيز الفيديو...",
    "Attempts to load and play this video again": "يحاول تحميل الفيديو وتشغيله مرة أخرى",
    "Video is not available yet. Please try again.": "الفيديو غير متاح بعد. يرجى المحاولة مرة أخرى.",
    "Video playback failed. Please try again.": "فشل تشغيل الفيديو. يرجى المحاولة مرة أخرى.",
    "Media download failed (%d).": "فشل تنزيل الوسائط (%d).",
    "Media is not available yet.": "الوسائط غير متاحة بعد.",
    "Shared location": "موقع تمت مشاركته",
    "Open Location": "فتح الموقع",
    "Open in Apple Maps": "فتح في خرائط Apple",
    "Open in Google Maps": "فتح في خرائط Google",
    "Copy Coordinates": "نسخ الإحداثيات",
    "Cancel": "إلغاء",
    "Typing...": "يكتب الآن...",
    "Choose Location": "اختر الموقع",
    "Search for a place": "ابحث عن مكان",
    "Locating": "جارٍ تحديد الموقع",
    "My Location": "موقعي",
    "Centers the map on your current location": "توسيط الخريطة على موقعك الحالي",
    "Send": "إرسال",
    "Sending...": "جارٍ الإرسال...",
    "Location Unavailable": "الموقع غير متاح",
    "Try again or choose a location manually on the map.": "حاول مرة أخرى أو اختر موقعًا يدويًا على الخريطة.",
    "Zoom in": "تكبير",
    "Zoom out": "تصغير",
    "That place could not be located. Try another search.": "تعذر العثور على هذا المكان. جرّب بحثًا آخر.",
    "Current location": "الموقع الحالي",
    "Selected location": "الموقع المحدد",
    "Your current location could not be found. Choose a location manually on the map or try again.": "تعذر العثور على موقعك الحالي. اختر موقعًا يدويًا على الخريطة أو حاول مرة أخرى.",
    "Location Services are disabled. Enable Location Services to share your current location.": "خدمات الموقع معطلة. فعّل خدمات الموقع لمشاركة موقعك الحالي.",
    "Location permission is required to share your current location.": "يلزم السماح بالوصول إلى الموقع لمشاركة موقعك الحالي.",
    "Current location is already being requested.": "جارٍ طلب الموقع الحالي بالفعل.",
    "Location sharing is not available on this platform.": "مشاركة الموقع غير متاحة على هذا النظام.",
    "The selected media could not be loaded.": "تعذر تحميل الوسائط المحددة.",
    "Videos must be %d seconds or shorter.": "يجب ألا تتجاوز مدة الفيديو %d ثانية.",
    "This video is too large. Choose a video smaller than %d MB.": "حجم الفيديو كبير جدًا. اختر فيديو أصغر من %d ميجابايت.",
    "This video could not be prepared for upload.": "تعذر تجهيز الفيديو للرفع.",
    "Microphone permission is required to record a voice note.": "يلزم السماح بالوصول إلى الميكروفون لتسجيل رسالة صوتية.",
    "No voice note is currently recording.": "لا توجد رسالة صوتية قيد التسجيل حاليًا.",
    "No internet connection. Reconnect, then retry your %@.": "لا يوجد اتصال بالإنترنت. أعد الاتصال ثم حاول إرسال %@ مرة أخرى.",
    "Sending your %@ took too long. Check your connection and retry.": "استغرق إرسال %@ وقتًا طويلًا. تحقق من الاتصال وحاول مرة أخرى.",
    "Chat is reconnecting. Retry your %@ in a moment.": "تتم إعادة الاتصال بالمحادثة. حاول إرسال %@ بعد قليل.",
    "Your chat session has expired. Reopen chat, then retry.": "انتهت جلسة المحادثة. أعد فتح المحادثة ثم حاول مرة أخرى.",
    "This %@ is too large to send. Choose a smaller file.": "حجم %@ كبير جدًا للإرسال. اختر ملفًا أصغر.",
    "Too many requests. Wait a moment, then retry your %@.": "طلبات كثيرة جدًا. انتظر قليلًا ثم حاول إرسال %@ مرة أخرى.",
    "The chat service is temporarily unavailable. Retry your %@ shortly.": "خدمة المحادثة غير متاحة مؤقتًا. حاول إرسال %@ بعد قليل.",
    "The chat service returned an unexpected response. Retry your %@.": "أعادت خدمة المحادثة استجابة غير متوقعة. حاول إرسال %@ مرة أخرى.",
    "This conversation is no longer available.": "هذه المحادثة لم تعد متاحة.",
    "Your location could not be prepared. Please share it again.": "تعذر تجهيز موقعك. يرجى مشاركته مرة أخرى.",
    "The original %@ is no longer available. Choose it again.": "لم يعد %@ الأصلي متاحًا. اختره مرة أخرى.",
    "We couldn't send your %@. Check your connection and retry.": "تعذر إرسال %@. تحقق من الاتصال وحاول مرة أخرى.",
    "Sending was interrupted. Tap Retry to send your %@.": "توقف الإرسال. اضغط على إعادة المحاولة لإرسال %@.",
    "photo": "الصورة",
    "video": "الفيديو",
    "voice note": "الرسالة الصوتية",
    "file": "الملف",
    "message": "الرسالة",
    "The backend returned an invalid response.": "أعاد الخادم استجابة غير صالحة.",
    "No chat room is available for this user.": "لا توجد غرفة محادثة متاحة لهذا المستخدم.",
    "The realtime connection is closed.": "اتصال المحادثة المباشر مغلق.",
    "The location message could not be encoded.": "تعذر تجهيز رسالة الموقع.",
    "Attachment": "مرفق"
  ]
}

extension InstaChatConfiguration {
  var localizer: InstaChatLocalizer {
    InstaChatLocalizer(language: language)
  }
}
