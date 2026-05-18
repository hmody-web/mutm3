// ═══════════════════════════════════════════════════════════════
//  دليل التكامل — كيفية ربط مشغل الريلز في listen_page.dart
// ═══════════════════════════════════════════════════════════════
//
//  1) أضف هذا الاستيراد في أعلى listen_page.dart:
//     import 'reels_player.dart';
//     import 'settings_page.dart'; // للوصول إلى ReelsModeNotifier
//
//  2) في initState داخل _ListenPageState، أضف:
//
//     @override
//     void initState() {
//       super.initState();
//       // ... الكود الموجود ...
//       ReelsModeNotifier.instance.load(); // ← أضف هذا
//     }
//
//  3) ابحث عن الدالة التي تفتح مشغل الفيديو المحلي (عادةً onTap لعناصر الفيديو)
//     وعدّلها هكذا:
//
//     void _openMedia(LocalMediaItem item) {
//       final index = _localItems.indexOf(item);
//
//       // ← استخدم الريلز إذا كان الوضع مفعّلاً والعنصر فيديو
//       if (ReelsModeNotifier.instance.value && item.isVideo) {
//         // فلتر الفيديوهات فقط
//         final videoItems = _localItems.where((e) => e.isVideo).toList();
//         final videoIndex = videoItems.indexOf(item);
//
//         Navigator.push(
//           context,
//           PageRouteBuilder(
//             pageBuilder: (_, __, ___) => ReelsVideoPlayer(
//               items: videoItems,
//               initialIndex: videoIndex < 0 ? 0 : videoIndex,
//               folders: _folders,
//               onFoldersChanged: () async {
//                 await _saveFolders();
//                 setState(() {});
//               },
//             ),
//             transitionsBuilder: (_, anim, __, child) {
//               return FadeTransition(
//                 opacity: anim,
//                 child: SlideTransition(
//                   position: Tween<Offset>(
//                     begin: const Offset(0, 1),
//                     end: Offset.zero,
//                   ).animate(CurvedAnimation(
//                       parent: anim, curve: Curves.easeOutCubic)),
//                   child: child,
//                 ),
//               );
//             },
//             transitionDuration: const Duration(milliseconds: 450),
//           ),
//         );
//         return;
//       }
//
//       // المشغل الأصلي للصوت أو عند إيقاف وضع الريلز
//       // ... كودك الموجود هنا ...
//     }
//
//  4) أضف reels_player.dart إلى pubspec.yaml كـ part من المشروع
//     (ليس package، بل ملف محلي في نفس مجلد lib)
//
//  ════════════════════════════════════════════════════════════
//  ملاحظات مهمة:
//  ════════════════════════════════════════════════════════════
//
//  ✦ ReelsModeNotifier.instance.value  → قيمة الوضع الحالي (true/false)
//  ✦ يعمل وضع الريلز على الفيديوهات فقط (item.isVideo == true)
//  ✦ الملفات الصوتية تبقى تعمل بالمشغل الأصلي دائماً
//  ✦ يتم حفظ حالة وضع الريلز في SharedPreferences بمفتاح 'reelsMode'
//
//  ════════════════════════════════════════════════════════════
//  ميزات مشغل الريلز:
//  ════════════════════════════════════════════════════════════
//
//  ✦ تصفح عبر السحب للأعلى والأسفل (PageView عمودي)
//  ✦ تكرار الفيديو (افتراضي: مفعّل)
//  ✦ تصفح تلقائي (ينتقل للفيديو التالي عند انتهاء الحالي)
//  ✦ إضافة الفيديو لمجلد
//  ✦ عنوان قابل للتوسع (27 حرف → كامل عند الضغط)
//  ✦ شريط تمرير سحبي في الأسفل
//  ✦ دبل تاب لعرض قلب متحرك
//  ✦ لوجو دندن في قائمة الجانب
//  ✦ مؤشر التقدم (X / Y)
//  ✦ إخفاء الـ UI تلقائياً بعد 3 ثواني
//  ✦ وضع الشاشة الكاملة (immersiveSticky)
//  ✦ Pre-loading للفيديوهات المجاورة
//  ✦ Dispose تلقائي للـ controllers البعيدة لتوفير الذاكرة