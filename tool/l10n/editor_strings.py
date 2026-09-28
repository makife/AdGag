# -*- coding: utf-8 -*-
"""Native video editor strings (Android Kotlin + iOS Swift) — THE source of truth.

The editors look strings up by their ENGLISH text: `tr("Cancel")`,
`tr("Clip {0} · trim", n)`. Edit here, then run

    python tool/l10n/build_editor_json.py

which writes android/app/src/main/assets/l10n/editor.json and
ios/Runner/Editor/AdGagL10n/editor.json, and lists any tr("…") in the native
code that has no entry here (those show in English).

Column order after the English key: tr es pt de fr it ru ar id ja ko.
"""

LANGS = ["tr", "es", "pt", "de", "fr", "it", "ru", "ar", "id", "ja", "ko"]

E = {}


def T(en, *xs):
    assert len(xs) == len(LANGS), (en, len(xs))
    assert en not in E, en
    E[en] = dict(zip(LANGS, xs))


# ------------------------------------------------------------------ top bar / general
T("Cancel", "Vazgeç", "Cancelar", "Cancelar", "Abbrechen", "Annuler", "Annulla", "Отмена", "إلغاء", "Batal", "キャンセル", "취소")
T("Next", "İleri", "Siguiente", "Avançar", "Weiter", "Suivant", "Avanti", "Далее", "التالي", "Lanjut", "次へ", "다음")
T("Done", "Tamam", "Listo", "Pronto", "Fertig", "OK", "Fatto", "Готово", "تم", "Selesai", "完了", "완료")
T("Delete", "Sil", "Eliminar", "Excluir", "Löschen", "Supprimer", "Elimina", "Удалить", "حذف", "Hapus", "削除", "삭제")
T("Add", "Ekle", "Añadir", "Adicionar", "Hinzufügen", "Ajouter", "Aggiungi", "Добавить", "إضافة", "Tambah", "追加", "추가")
T("Play", "Oynat", "Reproducir", "Reproduzir", "Abspielen", "Lire", "Riproduci", "Воспроизвести", "تشغيل", "Putar", "再生", "재생")
T("Try again", "Tekrar dene", "Reintentar", "Tentar de novo", "Erneut versuchen", "Réessayer", "Riprova", "Повторить", "أعد المحاولة", "Coba lagi", "再試行", "다시 시도")
T("Off", "Kapalı", "No", "Não", "Aus", "Non", "No", "Выкл.", "إيقاف", "Mati", "オフ", "끔")
T("Editor", "Editör", "Editor", "Editor", "Editor", "Éditeur", "Editor", "Редактор", "المحرر", "Editor", "エディター", "편집기")
T("{0} · drag up to edit", "{0} · düzenlemek için yukarı çek", "{0} · desliza hacia arriba para editar",
  "{0} · arraste para cima para editar", "{0} · zum Bearbeiten nach oben ziehen", "{0} · glissez vers le haut pour modifier",
  "{0} · trascina su per modificare", "{0} · потяните вверх, чтобы изменить", "{0} · اسحب لأعلى للتعديل",
  "{0} · tarik ke atas untuk mengedit", "{0} · 上にドラッグして編集", "{0} · 위로 끌어 편집")
T("Expand {0}", "{0} panelini aç", "Expandir {0}", "Expandir {0}", "{0} aufklappen", "Déplier {0}", "Espandi {0}",
  "Развернуть: {0}", "توسيع {0}", "Buka {0}", "{0}を開く", "{0} 펼치기")
T("Collapse {0}", "{0} panelini kapat", "Contraer {0}", "Recolher {0}", "{0} einklappen", "Replier {0}", "Comprimi {0}",
  "Свернуть: {0}", "طي {0}", "Tutup {0}", "{0}を閉じる", "{0} 접기")

# ------------------------------------------------------------------ tools
T("Text", "Yazı", "Texto", "Texto", "Text", "Texte", "Testo", "Текст", "نص", "Teks", "テキスト", "텍스트")
T("Text ({0})", "Yazı ({0})", "Texto ({0})", "Texto ({0})", "Text ({0})", "Texte ({0})", "Testo ({0})", "Текст ({0})",
  "نص ({0})", "Teks ({0})", "テキスト ({0})", "텍스트 ({0})")
T("Stickers", "Çıkartma", "Stickers", "Figurinhas", "Sticker", "Stickers", "Sticker", "Стикеры", "ملصقات", "Stiker", "ステッカー", "스티커")
T("Stickers ({0})", "Çıkartma ({0})", "Stickers ({0})", "Figurinhas ({0})", "Sticker ({0})", "Stickers ({0})", "Sticker ({0})",
  "Стикеры ({0})", "ملصقات ({0})", "Stiker ({0})", "ステッカー ({0})", "스티커 ({0})")
T("Sound FX", "Ses efekti", "Efectos de sonido", "Efeitos sonoros", "Soundeffekte", "Bruitages", "Effetti sonori",
  "Звуки", "مؤثرات صوتية", "Efek suara", "効果音", "효과음")
T("Sound FX ({0})", "Ses efekti ({0})", "Efectos de sonido ({0})", "Efeitos sonoros ({0})", "Soundeffekte ({0})",
  "Bruitages ({0})", "Effetti sonori ({0})", "Звуки ({0})", "مؤثرات صوتية ({0})", "Efek suara ({0})", "効果音 ({0})", "효과음 ({0})")
T("Rotate", "Döndür", "Girar", "Girar", "Drehen", "Pivoter", "Ruota", "Повернуть", "تدوير", "Putar", "回転", "회전")
T("Mute", "Sessiz", "Silenciar", "Silenciar", "Stumm", "Couper le son", "Muto", "Без звука", "كتم", "Bisukan", "ミュート", "음소거")
T("Muted", "Ses kapalı", "Silenciado", "Silenciado", "Stumm", "Son coupé", "Audio off", "Звук выкл.", "مكتوم", "Dibisukan", "ミュート中", "음소거됨")
T("Slow-mo", "Ağır çekim", "Cámara lenta", "Câmera lenta", "Zeitlupe", "Ralenti", "Rallentatore", "Замедление", "حركة بطيئة",
  "Gerak lambat", "スロー", "슬로모션")
T("Slow-mo ({0})", "Ağır çekim ({0})", "Cámara lenta ({0})", "Câmera lenta ({0})", "Zeitlupe ({0})", "Ralenti ({0})",
  "Rallentatore ({0})", "Замедление ({0})", "حركة بطيئة ({0})", "Gerak lambat ({0})", "スロー ({0})", "슬로모션 ({0})")
T("slow-mo", "ağır çekim", "cámara lenta", "câmera lenta", "Zeitlupe", "ralenti", "rallentatore", "замедление", "حركة بطيئة",
  "gerak lambat", "スロー", "슬로모션")
T("Effects", "Efektler", "Efectos", "Efeitos", "Effekte", "Effets", "Effetti", "Эффекты", "تأثيرات", "Efek", "エフェクト", "효과")
T("Music", "Müzik", "Música", "Música", "Musik", "Musique", "Musica", "Музыка", "موسيقى", "Musik", "音楽", "음악")
T("Add music", "Müzik ekle", "Añadir música", "Adicionar música", "Musik hinzufügen", "Ajouter une musique", "Aggiungi musica",
  "Добавить музыку", "إضافة موسيقى", "Tambah musik", "音楽を追加", "음악 추가")

# ------------------------------------------------------------------ status / errors
T("Exporting your Ad…", "Reklamın hazırlanıyor…", "Preparando tu anuncio…", "Preparando seu anúncio…", "Deine Werbung wird erstellt…",
  "Création de ta pub…", "Preparazione della tua pubblicità…", "Готовим твою рекламу…", "جارٍ تجهيز إعلانك…",
  "Menyiapkan iklanmu…", "広告を書き出しています…", "광고를 만드는 중…")
T("Preparing music…", "Müzik hazırlanıyor…", "Preparando la música…", "Preparando a música…", "Musik wird vorbereitet…",
  "Préparation de la musique…", "Preparazione della musica…", "Готовим музыку…", "جارٍ تجهيز الموسيقى…", "Menyiapkan musik…",
  "音楽を準備しています…", "음악 준비 중…")
T("Preview problem: {0}", "Önizleme sorunu: {0}", "Problema de vista previa: {0}", "Problema na prévia: {0}",
  "Vorschau-Problem: {0}", "Problème d'aperçu : {0}", "Problema di anteprima: {0}", "Ошибка предпросмотра: {0}",
  "مشكلة في المعاينة: {0}", "Masalah pratinjau: {0}", "プレビューの問題: {0}", "미리보기 문제: {0}")
T("Export failed: {0}", "Dışa aktarma başarısız: {0}", "Error al exportar: {0}", "Falha ao exportar: {0}",
  "Export fehlgeschlagen: {0}", "Échec de l'export : {0}", "Esportazione non riuscita: {0}", "Не удалось экспортировать: {0}",
  "فشل التصدير: {0}", "Ekspor gagal: {0}", "書き出しに失敗しました: {0}", "내보내기 실패: {0}")
T("Export failed", "Dışa aktarma başarısız", "Error al exportar", "Falha ao exportar", "Export fehlgeschlagen", "Échec de l'export",
  "Esportazione non riuscita", "Не удалось экспортировать", "فشل التصدير", "Ekspor gagal", "書き出しに失敗しました", "내보내기 실패")
T("Couldn't start the export.", "Dışa aktarma başlatılamadı.", "No se pudo iniciar la exportación.", "Não foi possível iniciar a exportação.",
  "Export konnte nicht gestartet werden.", "Impossible de lancer l'export.", "Impossibile avviare l'esportazione.",
  "Не удалось начать экспорт.", "تعذّر بدء التصدير.", "Tidak dapat memulai ekspor.", "書き出しを開始できませんでした。", "내보내기를 시작할 수 없어요.")
T("Couldn't read that audio file.", "Bu ses dosyası okunamadı.", "No se pudo leer ese archivo de audio.",
  "Não foi possível ler esse arquivo de áudio.", "Diese Audiodatei konnte nicht gelesen werden.", "Impossible de lire ce fichier audio.",
  "Impossibile leggere questo file audio.", "Не удалось прочитать этот аудиофайл.", "تعذّرت قراءة هذا الملف الصوتي.",
  "Tidak dapat membaca file audio itu.", "この音声ファイルを読み込めませんでした。", "이 오디오 파일을 읽을 수 없어요.")
T("Couldn't change the music speed.", "Müziğin hızı değiştirilemedi.", "No se pudo cambiar la velocidad de la música.",
  "Não foi possível mudar a velocidade da música.", "Das Musiktempo konnte nicht geändert werden.",
  "Impossible de changer la vitesse de la musique.", "Impossibile cambiare la velocità della musica.",
  "Не удалось изменить скорость музыки.", "تعذّر تغيير سرعة الموسيقى.", "Tidak dapat mengubah kecepatan musik.",
  "音楽の速度を変更できませんでした。", "음악 속도를 바꿀 수 없어요.")
T("Couldn't prepare the music preview.", "Müzik önizlemesi hazırlanamadı.", "No se pudo preparar la vista previa de la música.",
  "Não foi possível preparar a prévia da música.", "Die Musikvorschau konnte nicht vorbereitet werden.",
  "Impossible de préparer l'aperçu de la musique.", "Impossibile preparare l'anteprima della musica.",
  "Не удалось подготовить предпросмотр музыки.", "تعذّر تجهيز معاينة الموسيقى.", "Tidak dapat menyiapkan pratinjau musik.",
  "音楽のプレビューを準備できませんでした。", "음악 미리보기를 준비할 수 없어요.")
T("No room for slow motion — the Ad is already 30s. Trim it first.",
  "Ağır çekime yer yok — reklam zaten 30 sn. Önce kırp.",
  "No hay espacio para cámara lenta: el anuncio ya dura 30 s. Recórtalo primero.",
  "Sem espaço para câmera lenta: o anúncio já tem 30 s. Corte-o primeiro.",
  "Kein Platz für Zeitlupe – die Werbung ist schon 30 s lang. Kürze sie zuerst.",
  "Pas de place pour un ralenti : la pub fait déjà 30 s. Coupe-la d'abord.",
  "Non c'è spazio per il rallentatore: la pubblicità dura già 30 s. Prima tagliala.",
  "Нет места для замедления — реклама уже 30 с. Сначала обрежьте её.",
  "لا مجال للحركة البطيئة — مدة الإعلان 30 ثانية بالفعل. قصّه أولاً.",
  "Tidak ada ruang untuk gerak lambat — iklan sudah 30 dtk. Potong dulu.",
  "スローを入れる余裕がありません。広告はすでに30秒です。先にトリミングしてください。",
  "슬로모션을 넣을 공간이 없어요. 광고가 이미 30초예요. 먼저 잘라 주세요.")
T("Shortened the end by {0} so slow motion fits in 30s.",
  "Ağır çekim 30 sn'ye sığsın diye sondan {0} kısaltıldı.",
  "Se recortó el final {0} para que la cámara lenta quepa en 30 s.",
  "O final foi encurtado em {0} para a câmera lenta caber em 30 s.",
  "Das Ende wurde um {0} gekürzt, damit die Zeitlupe in 30 s passt.",
  "La fin a été raccourcie de {0} pour que le ralenti tienne en 30 s.",
  "Il finale è stato accorciato di {0} perché il rallentatore stia in 30 s.",
  "Конец укорочен на {0}, чтобы замедление уместилось в 30 с.",
  "تم تقصير النهاية بمقدار {0} لتتسع الحركة البطيئة في 30 ثانية.",
  "Bagian akhir dipotong {0} agar gerak lambat muat dalam 30 dtk.",
  "スローが30秒に収まるよう、最後を{0}短くしました。",
  "슬로모션이 30초에 맞도록 끝부분을 {0} 줄였어요.")

# ------------------------------------------------------------------ timeline
T("Clips", "Klipler", "Clips", "Clipes", "Clips", "Clips", "Clip", "Клипы", "المقاطع", "Klip", "クリップ", "클립")
T("Trim", "Kırp", "Recortar", "Cortar", "Kürzen", "Couper", "Taglia", "Обрезка", "قص", "Potong", "トリミング", "자르기")
T("Clip {0} · trim", "Klip {0} · kırp", "Clip {0} · recortar", "Clipe {0} · cortar", "Clip {0} · kürzen", "Clip {0} · couper",
  "Clip {0} · taglia", "Клип {0} · обрезка", "المقطع {0} · قص", "Klip {0} · potong", "クリップ{0} · トリミング", "클립 {0} · 자르기")
T("Delete clip", "Klibi sil", "Eliminar clip", "Excluir clipe", "Clip löschen", "Supprimer le clip", "Elimina clip",
  "Удалить клип", "حذف المقطع", "Hapus klip", "クリップを削除", "클립 삭제")
T("Slow motion", "Ağır çekim", "Cámara lenta", "Câmera lenta", "Zeitlupe", "Ralenti", "Rallentatore", "Замедление",
  "حركة بطيئة", "Gerak lambat", "スローモーション", "슬로모션")
T("Slow motion · tap one to select", "Ağır çekim · seçmek için birine dokun", "Cámara lenta · toca uno para seleccionarlo",
  "Câmera lenta · toque em um para selecionar", "Zeitlupe · zum Auswählen antippen", "Ralenti · touche-en un pour le choisir",
  "Rallentatore · tocca per selezionare", "Замедление · нажмите, чтобы выбрать", "حركة بطيئة · اضغط لتحديد واحدة",
  "Gerak lambat · ketuk untuk memilih", "スロー · タップして選択", "슬로모션 · 탭해서 선택")
T("Add slow motion", "Ağır çekim ekle", "Añadir cámara lenta", "Adicionar câmera lenta", "Zeitlupe hinzufügen", "Ajouter un ralenti",
  "Aggiungi rallentatore", "Добавить замедление", "إضافة حركة بطيئة", "Tambah gerak lambat", "スローを追加", "슬로모션 추가")
T("Text, stickers & sounds · tap one to select", "Yazı, çıkartma ve sesler · seçmek için birine dokun",
  "Texto, stickers y sonidos · toca uno para seleccionarlo", "Texto, figurinhas e sons · toque em um para selecionar",
  "Text, Sticker & Sounds · zum Auswählen antippen", "Texte, stickers et sons · touche-en un pour le choisir",
  "Testo, sticker e suoni · tocca per selezionare", "Текст, стикеры и звуки · нажмите, чтобы выбрать",
  "نصوص وملصقات وأصوات · اضغط لتحديد واحد", "Teks, stiker & suara · ketuk untuk memilih",
  "テキスト・ステッカー・効果音 · タップして選択", "텍스트, 스티커, 효과음 · 탭해서 선택")
T("Add text", "Yazı ekle", "Añadir texto", "Adicionar texto", "Text hinzufügen", "Ajouter du texte", "Aggiungi testo",
  "Добавить текст", "إضافة نص", "Tambah teks", "テキストを追加", "텍스트 추가")
T("loop", "döngü", "bucle", "loop", "Schleife", "boucle", "loop", "повтор", "تكرار", "ulang", "ループ", "반복")
T("Song section", "Şarkı bölümü", "Parte de la canción", "Trecho da música", "Songabschnitt", "Passage de la chanson",
  "Parte del brano", "Фрагмент песни", "مقطع الأغنية", "Bagian lagu", "曲の範囲", "노래 구간")
T("{0} of {1}", "{0} / {1}", "{0} de {1}", "{0} de {1}", "{0} von {1}", "{0} sur {1}", "{0} di {1}", "{0} из {1}",
  "{0} من {1}", "{0} dari {1}", "{0} / {1}", "{0} / {1}")
T("Music settings", "Müzik ayarları", "Ajustes de música", "Configurações de música", "Musikeinstellungen", "Réglages de la musique",
  "Impostazioni musica", "Настройки музыки", "إعدادات الموسيقى", "Pengaturan musik", "音楽の設定", "음악 설정")
T("Record another clip", "Başka bir klip çek", "Grabar otro clip", "Gravar outro clipe", "Weiteren Clip aufnehmen",
  "Filmer un autre clip", "Registra un'altra clip", "Снять ещё клип", "تسجيل مقطع آخر", "Rekam klip lain", "別のクリップを撮る",
  "클립 하나 더 찍기")
T("Transition effect", "Geçiş efekti", "Efecto de transición", "Efeito de transição", "Übergangseffekt", "Effet de transition",
  "Effetto di transizione", "Эффект перехода", "تأثير الانتقال", "Efek transisi", "トランジション", "전환 효과")
T("Sticker", "Çıkartma", "Sticker", "Figurinha", "Sticker", "Sticker", "Sticker", "Стикер", "ملصق", "Stiker", "ステッカー", "스티커")
T("Sound", "Ses", "Sonido", "Som", "Sound", "Son", "Suono", "Звук", "صوت", "Suara", "効果音", "효과음")

# ------------------------------------------------------------------ sheets
T("Speed", "Hız", "Velocidad", "Velocidade", "Tempo", "Vitesse", "Velocità", "Скорость", "السرعة", "Kecepatan", "速度", "속도")
T("Loop to fill the video", "Video bitene kadar tekrarla", "Repetir hasta llenar el video", "Repetir até preencher o vídeo",
  "Wiederholen bis zum Videoende", "Boucler jusqu'à la fin de la vidéo", "Ripeti fino alla fine del video",
  "Повторять до конца видео", "تكرار حتى نهاية الفيديو", "Ulangi sampai video selesai", "動画の最後までループ", "영상 끝까지 반복")
T("Repeats the selected part until the video ends", "Seçili bölüm video bitene kadar tekrar eder",
  "Repite la parte seleccionada hasta que termine el video", "Repete o trecho selecionado até o vídeo acabar",
  "Wiederholt den gewählten Teil bis zum Ende des Videos", "Répète la partie choisie jusqu'à la fin de la vidéo",
  "Ripete la parte selezionata fino alla fine del video", "Повторяет выбранную часть до конца видео",
  "يكرر الجزء المحدد حتى ينتهي الفيديو", "Mengulang bagian terpilih sampai video selesai",
  "選んだ部分を動画の最後まで繰り返します", "선택한 부분을 영상이 끝날 때까지 반복해요")
T("Fade in", "Yavaşça gir", "Aparecer", "Surgir", "Einblenden", "Fondu d'entrée", "Dissolvenza in entrata", "Появление",
  "ظهور تدريجي", "Muncul perlahan", "フェードイン", "페이드 인")
T("Fade out", "Yavaşça çık", "Desvanecer", "Sumir", "Ausblenden", "Fondu de sortie", "Dissolvenza in uscita", "Затухание",
  "اختفاء تدريجي", "Hilang perlahan", "フェードアウト", "페이드 아웃")
T("Replace music", "Müziği değiştir", "Cambiar música", "Trocar música", "Musik ersetzen", "Changer la musique", "Sostituisci musica",
  "Заменить музыку", "استبدال الموسيقى", "Ganti musik", "音楽を変更", "음악 바꾸기")
T("Remove music", "Müziği kaldır", "Quitar música", "Remover música", "Musik entfernen", "Retirer la musique", "Rimuovi musica",
  "Убрать музыку", "إزالة الموسيقى", "Hapus musik", "音楽を削除", "음악 삭제")
T("{0} – {1} of your clips plays at {2}. Drag the edges on the Speed row to change which part.",
  "Kliplerinin {0} – {1} arası {2} hızında oynar. Hangi bölüm olacağını Hız satırındaki kenarları sürükleyerek değiştir.",
  "De {0} a {1} de tus clips se reproduce a {2}. Arrastra los bordes en la fila de Velocidad para cambiar la parte.",
  "De {0} a {1} dos seus clipes toca a {2}. Arraste as bordas na linha Velocidade para mudar o trecho.",
  "{0} – {1} deiner Clips laufen mit {2}. Zieh die Ränder in der Tempo-Zeile, um den Teil zu ändern.",
  "De {0} à {1} de tes clips passe à {2}. Fais glisser les bords sur la ligne Vitesse pour changer la partie.",
  "Da {0} a {1} delle tue clip va a {2}. Trascina i bordi nella riga Velocità per cambiare la parte.",
  "С {0} по {1} ваших клипов идёт со скоростью {2}. Перетащите края в строке «Скорость», чтобы изменить участок.",
  "من {0} إلى {1} من مقاطعك يُعرض بسرعة {2}. اسحب الحواف في صف السرعة لتغيير الجزء.",
  "{0} – {1} dari klipmu diputar pada {2}. Seret tepinya di baris Kecepatan untuk mengubah bagian.",
  "クリップの{0}〜{1}が{2}で再生されます。範囲は「速度」の行の端をドラッグして変更できます。",
  "클립의 {0}~{1} 구간이 {2}로 재생돼요. 속도 줄의 가장자리를 끌어 구간을 바꾸세요.")
T("Your Ad: {0} of 0:30.", "Reklamın: {0} / 0:30.", "Tu anuncio: {0} de 0:30.", "Seu anúncio: {0} de 0:30.",
  "Deine Werbung: {0} von 0:30.", "Ta pub : {0} sur 0:30.", "La tua pubblicità: {0} di 0:30.", "Твоя реклама: {0} из 0:30.",
  "إعلانك: {0} من 0:30.", "Iklanmu: {0} dari 0:30.", "広告の長さ: {0} / 0:30", "내 광고: {0} / 0:30")
T("{0} would make the Ad longer than 30s — shorten the range first.",
  "{0} reklamı 30 sn'den uzun yapar — önce aralığı kısalt.",
  "{0} haría que el anuncio dure más de 30 s: acorta el rango primero.",
  "{0} deixaria o anúncio com mais de 30 s — encurte o trecho primeiro.",
  "{0} würde die Werbung länger als 30 s machen – kürze zuerst den Bereich.",
  "{0} rendrait la pub plus longue que 30 s : raccourcis d'abord la plage.",
  "{0} renderebbe la pubblicità più lunga di 30 s: prima accorcia l'intervallo.",
  "{0} сделает рекламу длиннее 30 с — сначала сократите участок.",
  "{0} سيجعل الإعلان أطول من 30 ثانية — قصّر النطاق أولاً.",
  "{0} akan membuat iklan lebih dari 30 dtk — perpendek rentangnya dulu.",
  "{0}にすると広告が30秒を超えます。先に範囲を短くしてください。",
  "{0}로 하면 광고가 30초를 넘어요. 먼저 구간을 줄이세요.")
T("Whole video", "Tüm video", "Todo el video", "Vídeo inteiro", "Ganzes Video", "Toute la vidéo", "Tutto il video", "Всё видео",
  "الفيديو كاملاً", "Seluruh video", "動画全体", "영상 전체")
T("Remove slow motion", "Ağır çekimi kaldır", "Quitar cámara lenta", "Remover câmera lenta", "Zeitlupe entfernen",
  "Retirer le ralenti", "Rimuovi rallentatore", "Убрать замедление", "إزالة الحركة البطيئة", "Hapus gerak lambat",
  "スローを削除", "슬로모션 삭제")
T("Live preview of effects is off on this device. The effect is still applied to your Ad.",
  "Bu cihazda efektlerin canlı önizlemesi kapalı. Efekt yine de reklamına uygulanır.",
  "La vista previa de efectos está desactivada en este dispositivo. El efecto se aplica igual a tu anuncio.",
  "A prévia dos efeitos está desativada neste aparelho. O efeito ainda é aplicado ao seu anúncio.",
  "Die Live-Vorschau von Effekten ist auf diesem Gerät aus. Der Effekt wird trotzdem auf deine Werbung angewendet.",
  "L'aperçu en direct des effets est désactivé sur cet appareil. L'effet est quand même appliqué à ta pub.",
  "L'anteprima degli effetti è disattivata su questo dispositivo. L'effetto viene comunque applicato alla pubblicità.",
  "Предпросмотр эффектов на этом устройстве отключён. Эффект всё равно будет применён к рекламе.",
  "المعاينة المباشرة للتأثيرات متوقفة على هذا الجهاز. سيُطبَّق التأثير على إعلانك مع ذلك.",
  "Pratinjau langsung efek nonaktif di perangkat ini. Efek tetap diterapkan ke iklanmu.",
  "この端末ではエフェクトのライブプレビューがオフです。エフェクトは広告に適用されます。",
  "이 기기에서는 효과 실시간 미리보기가 꺼져 있어요. 효과는 광고에 그대로 적용돼요.")
T("Clip {0} → Clip {1}", "Klip {0} → Klip {1}", "Clip {0} → Clip {1}", "Clipe {0} → Clipe {1}", "Clip {0} → Clip {1}",
  "Clip {0} → Clip {1}", "Clip {0} → Clip {1}", "Клип {0} → Клип {1}", "المقطع {0} ← المقطع {1}", "Klip {0} → Klip {1}",
  "クリップ{0} → クリップ{1}", "클립 {0} → 클립 {1}")
T("Duration", "Süre", "Duración", "Duração", "Dauer", "Durée", "Durata", "Длительность", "المدة", "Durasi", "長さ", "길이")

# ------------------------------------------------------------------ sound / sticker panels
T("All", "Tümü", "Todo", "Tudo", "Alle", "Tout", "Tutti", "Все", "الكل", "Semua", "すべて", "전체")
T("Listen", "Dinle", "Escuchar", "Ouvir", "Anhören", "Écouter", "Ascolta", "Прослушать", "استماع", "Dengar", "試聴", "듣기")
T("Use this sound", "Bu sesi kullan", "Usar este sonido", "Usar este som", "Diesen Sound nehmen", "Utiliser ce son",
  "Usa questo suono", "Использовать этот звук", "استخدام هذا الصوت", "Pakai suara ini", "この効果音を使う", "이 효과음 사용")
T("Change sound", "Sesi değiştir", "Cambiar sonido", "Trocar som", "Sound ändern", "Changer le son", "Cambia suono",
  "Заменить звук", "تغيير الصوت", "Ganti suara", "効果音を変更", "효과음 바꾸기")
T("Change sticker", "Çıkartmayı değiştir", "Cambiar sticker", "Trocar figurinha", "Sticker ändern", "Changer de sticker",
  "Cambia sticker", "Заменить стикер", "تغيير الملصق", "Ganti stiker", "ステッカーを変更", "스티커 바꾸기")
T("Flip", "Çevir", "Voltear", "Espelhar", "Spiegeln", "Retourner", "Rifletti", "Отразить", "قلب", "Balik", "反転", "뒤집기")
T("Animated emoji: Google Noto Emoji (CC BY 4.0)", "Animasyonlu emoji: Google Noto Emoji (CC BY 4.0)",
  "Emoji animados: Google Noto Emoji (CC BY 4.0)", "Emojis animados: Google Noto Emoji (CC BY 4.0)",
  "Animierte Emojis: Google Noto Emoji (CC BY 4.0)", "Emojis animés : Google Noto Emoji (CC BY 4.0)",
  "Emoji animate: Google Noto Emoji (CC BY 4.0)", "Анимированные эмодзи: Google Noto Emoji (CC BY 4.0)",
  "إيموجي متحركة: Google Noto Emoji (CC BY 4.0)", "Emoji animasi: Google Noto Emoji (CC BY 4.0)",
  "アニメ絵文字: Google Noto Emoji (CC BY 4.0)", "움직이는 이모지: Google Noto Emoji (CC BY 4.0)")

# ------------------------------------------------------------------ text panel
T("Your text", "Yazın", "Tu texto", "Seu texto", "Dein Text", "Ton texte", "Il tuo testo", "Твой текст", "نصك", "Teksmu",
  "テキストを入力", "텍스트 입력")
T("Type something", "Bir şey yaz", "Escribe algo", "Digite algo", "Schreib etwas", "Écris quelque chose", "Scrivi qualcosa",
  "Напишите что-нибудь", "اكتب شيئاً", "Ketik sesuatu", "何か入力", "무엇이든 입력")
T("Font", "Yazı tipi", "Fuente", "Fonte", "Schrift", "Police", "Font", "Шрифт", "الخط", "Font", "フォント", "글꼴")
T("Style", "Stil", "Estilo", "Estilo", "Stil", "Style", "Stile", "Стиль", "النمط", "Gaya", "スタイル", "스타일")
T("In", "Giriş", "Entrada", "Entrada", "Rein", "Entrée", "Entrata", "Вход", "دخول", "Masuk", "イン", "등장")
T("Out", "Çıkış", "Salida", "Saída", "Raus", "Sortie", "Uscita", "Выход", "خروج", "Keluar", "アウト", "퇴장")
T("Color", "Renk", "Color", "Cor", "Farbe", "Couleur", "Colore", "Цвет", "اللون", "Warna", "色", "색상")
T("Size", "Boyut", "Tamaño", "Tamanho", "Größe", "Taille", "Dimensione", "Размер", "الحجم", "Ukuran", "サイズ", "크기")
T("Effect colour", "Efekt rengi", "Color del efecto", "Cor do efeito", "Effektfarbe", "Couleur de l'effet", "Colore effetto",
  "Цвет эффекта", "لون التأثير", "Warna efek", "効果の色", "효과 색상")
T("Opacity", "Opaklık", "Opacidad", "Opacidade", "Deckkraft", "Opacité", "Opacità", "Непрозрачность", "العتامة", "Opasitas",
  "不透明度", "불투명도")
T("Letter spacing", "Harf aralığı", "Espaciado", "Espaçamento", "Zeichenabstand", "Espacement", "Spaziatura", "Межбуквенный интервал",
  "تباعد الأحرف", "Jarak huruf", "文字間隔", "자간")
T("Straighten", "Düzelt", "Enderezar", "Endireitar", "Geraderücken", "Redresser", "Raddrizza", "Выровнять", "تسوية",
  "Luruskan", "まっすぐにする", "똑바로")
T("Left", "Sol", "Izquierda", "Esquerda", "Links", "Gauche", "Sinistra", "Слева", "يسار", "Kiri", "左", "왼쪽")
T("Center", "Orta", "Centro", "Centro", "Mitte", "Centre", "Centro", "По центру", "وسط", "Tengah", "中央", "가운데")
T("Right", "Sağ", "Derecha", "Direita", "Rechts", "Droite", "Destra", "Справа", "يمين", "Kanan", "右", "오른쪽")

# ------------------------------------------------------------------ transitions
T("Cut", "Kesme", "Corte", "Corte", "Schnitt", "Cut", "Stacco", "Склейка", "قطع", "Potong", "カット", "컷")
T("Dip to black", "Siyaha geçiş", "Fundido a negro", "Fade para preto", "Schwarzblende", "Fondu au noir", "Dissolvenza al nero",
  "Через чёрный", "تلاشٍ إلى الأسود", "Pudar ke hitam", "黒フェード", "블랙 페이드")
T("Slide ←", "Kaydır ←", "Deslizar ←", "Deslizar ←", "Schieben ←", "Glisser ←", "Scorri ←", "Сдвиг ←", "انزلاق ←", "Geser ←",
  "スライド ←", "슬라이드 ←")
T("Slide →", "Kaydır →", "Deslizar →", "Deslizar →", "Schieben →", "Glisser →", "Scorri →", "Сдвиг →", "انزلاق →", "Geser →",
  "スライド →", "슬라이드 →")
T("Slide ↑", "Kaydır ↑", "Deslizar ↑", "Deslizar ↑", "Schieben ↑", "Glisser ↑", "Scorri ↑", "Сдвиг ↑", "انزلاق ↑", "Geser ↑",
  "スライド ↑", "슬라이드 ↑")
T("Slide ↓", "Kaydır ↓", "Deslizar ↓", "Deslizar ↓", "Schieben ↓", "Glisser ↓", "Scorri ↓", "Сдвиг ↓", "انزلاق ↓", "Geser ↓",
  "スライド ↓", "슬라이드 ↓")
T("Zoom in", "Yakınlaş", "Acercar", "Aproximar", "Heranzoomen", "Zoom avant", "Zoom avanti", "Приближение", "تكبير",
  "Perbesar", "ズームイン", "줌 인")
T("Zoom out", "Uzaklaş", "Alejar", "Afastar", "Herauszoomen", "Zoom arrière", "Zoom indietro", "Отдаление", "تصغير",
  "Perkecil", "ズームアウト", "줌 아웃")
T("Spin", "Döndür", "Girar", "Girar", "Drehen", "Tourner", "Ruota", "Вращение", "دوران", "Putar", "回転", "회전")

# ------------------------------------------------------------------ look effects
T("Original", "Orijinal", "Original", "Original", "Original", "Original", "Originale", "Оригинал", "الأصلي", "Asli", "オリジナル", "원본")
T("B&W", "Siyah-beyaz", "B/N", "P&B", "S/W", "N&B", "B/N", "Ч/Б", "أبيض وأسود", "H&P", "白黒", "흑백")
T("Sepia", "Sepya", "Sepia", "Sépia", "Sepia", "Sépia", "Seppia", "Сепия", "بني داكن", "Sepia", "セピア", "세피아")
T("Vintage", "Vintage", "Vintage", "Vintage", "Vintage", "Vintage", "Vintage", "Винтаж", "عتيق", "Vintage", "ヴィンテージ", "빈티지")
T("Cool", "Soğuk", "Frío", "Frio", "Kühl", "Froid", "Freddo", "Холодный", "بارد", "Dingin", "クール", "차갑게")
T("Warm", "Sıcak", "Cálido", "Quente", "Warm", "Chaud", "Caldo", "Тёплый", "دافئ", "Hangat", "ウォーム", "따뜻하게")
T("Vivid", "Canlı", "Vivo", "Vívido", "Kräftig", "Vif", "Vivido", "Яркий", "زاهٍ", "Cerah", "ビビッド", "선명하게")
T("Negative", "Negatif", "Negativo", "Negativo", "Negativ", "Négatif", "Negativo", "Негатив", "سلبي", "Negatif", "ネガ", "네거티브")
T("Fisheye", "Balıkgözü", "Ojo de pez", "Olho de peixe", "Fischauge", "Fisheye", "Fisheye", "Рыбий глаз", "عين السمكة",
  "Mata ikan", "魚眼", "어안")
T("Old TV", "Eski TV", "TV antigua", "TV antiga", "Alter Fernseher", "Vieille télé", "TV d'epoca", "Старый ТВ", "تلفاز قديم",
  "TV jadul", "古いテレビ", "옛날 TV")
T("Static", "Parazit", "Estática", "Chiado", "Rauschen", "Parasites", "Disturbo", "Помехи", "تشويش", "Semut", "砂嵐", "지지직")
T("VHS", "VHS", "VHS", "VHS", "VHS", "VHS", "VHS", "VHS", "VHS", "VHS", "VHS", "VHS")
T("Glitch", "Glitch", "Glitch", "Glitch", "Glitch", "Glitch", "Glitch", "Глитч", "خلل", "Glitch", "グリッチ", "글리치")
T("Pixel", "Piksel", "Píxel", "Pixel", "Pixel", "Pixel", "Pixel", "Пиксели", "بكسل", "Piksel", "ピクセル", "픽셀")
T("Mirror", "Ayna", "Espejo", "Espelho", "Spiegel", "Miroir", "Specchio", "Зеркало", "مرآة", "Cermin", "ミラー", "거울")
T("Flowers", "Çiçekler", "Flores", "Flores", "Blumen", "Fleurs", "Fiori", "Цветы", "زهور", "Bunga", "花", "꽃")
T("Hearts", "Kalpler", "Corazones", "Corações", "Herzen", "Cœurs", "Cuori", "Сердечки", "قلوب", "Hati", "ハート", "하트")
T("Film", "Film", "Película", "Filme", "Film", "Pellicule", "Pellicola", "Плёнка", "فيلم", "Film", "フィルム", "필름")
T("Ivy", "Sarmaşık", "Hiedra", "Hera", "Efeu", "Lierre", "Edera", "Плющ", "لبلاب", "Tanaman rambat", "ツタ", "담쟁이")
T("Balloons", "Balonlar", "Globos", "Balões", "Luftballons", "Ballons", "Palloncini", "Шарики", "بالونات", "Balon", "風船", "풍선")
T("Stars", "Yıldızlar", "Estrellas", "Estrelas", "Sterne", "Étoiles", "Stelle", "Звёзды", "نجوم", "Bintang", "星", "별")
T("Confetti", "Konfeti", "Confeti", "Confete", "Konfetti", "Confettis", "Coriandoli", "Конфетти", "قصاصات ملونة", "Konfeti",
  "紙吹雪", "색종이")

# ------------------------------------------------------------------ text styles
T("Plain", "Sade", "Simple", "Simples", "Schlicht", "Simple", "Semplice", "Обычный", "عادي", "Polos", "プレーン", "기본")
T("Outline", "Kontur", "Contorno", "Contorno", "Kontur", "Contour", "Contorno", "Контур", "حدود", "Garis tepi", "縁取り", "외곽선")
T("Shadow", "Gölge", "Sombra", "Sombra", "Schatten", "Ombre", "Ombra", "Тень", "ظل", "Bayangan", "影", "그림자")
T("Glow", "Işıltı", "Brillo", "Brilho", "Leuchten", "Lueur", "Bagliore", "Свечение", "توهج", "Pendar", "グロー", "글로우")
T("Neon", "Neon", "Neón", "Neon", "Neon", "Néon", "Neon", "Неон", "نيون", "Neon", "ネオン", "네온")
T("Box", "Kutu", "Caja", "Caixa", "Box", "Boîte", "Riquadro", "Плашка", "صندوق", "Kotak", "ボックス", "박스")
T("Pill", "Hap", "Píldora", "Pílula", "Pille", "Pilule", "Pillola", "Капсула", "كبسولة", "Pil", "ピル", "알약")
T("Marker", "Fosforlu", "Marcador", "Marca-texto", "Marker", "Surligneur", "Evidenziatore", "Маркер", "قلم تمييز", "Stabilo",
  "マーカー", "형광펜")
T("Hollow", "Boş", "Hueco", "Vazado", "Hohl", "Évidé", "Vuoto", "Полый", "مجوف", "Berongga", "中抜き", "속 빈")
T("3D", "3B", "3D", "3D", "3D", "3D", "3D", "3D", "ثلاثي الأبعاد", "3D", "3D", "3D")
T("Comic", "Çizgi roman", "Cómic", "Quadrinhos", "Comic", "BD", "Fumetto", "Комикс", "كوميك", "Komik", "コミック", "코믹")
T("Retro", "Retro", "Retro", "Retrô", "Retro", "Rétro", "Retrò", "Ретро", "كلاسيكي", "Retro", "レトロ", "레트로")
T("Gold", "Altın", "Oro", "Ouro", "Gold", "Or", "Oro", "Золото", "ذهبي", "Emas", "ゴールド", "골드")
T("Sunset", "Gün batımı", "Atardecer", "Pôr do sol", "Sonnenuntergang", "Coucher de soleil", "Tramonto", "Закат", "غروب",
  "Senja", "夕焼け", "노을")
T("Ocean", "Okyanus", "Océano", "Oceano", "Ozean", "Océan", "Oceano", "Океан", "محيط", "Samudra", "オーシャン", "바다")
T("Rainbow", "Gökkuşağı", "Arcoíris", "Arco-íris", "Regenbogen", "Arc-en-ciel", "Arcobaleno", "Радуга", "قوس قزح", "Pelangi",
  "レインボー", "무지개")
T("Long shadow", "Uzun gölge", "Sombra larga", "Sombra longa", "Langer Schatten", "Ombre longue", "Ombra lunga", "Длинная тень",
  "ظل طويل", "Bayangan panjang", "ロングシャドウ", "긴 그림자")
T("Double", "Çift", "Doble", "Duplo", "Doppelt", "Double", "Doppio", "Двойной", "مزدوج", "Ganda", "ダブル", "이중")
T("Chrome", "Krom", "Cromo", "Cromado", "Chrom", "Chrome", "Cromato", "Хром", "كروم", "Krom", "クローム", "크롬")
T("Fire", "Ateş", "Fuego", "Fogo", "Feuer", "Feu", "Fuoco", "Огонь", "نار", "Api", "炎", "불")
T("Ice", "Buz", "Hielo", "Gelo", "Eis", "Glace", "Ghiaccio", "Лёд", "جليد", "Es", "氷", "얼음")
T("Split", "Bölünmüş", "Dividido", "Dividido", "Geteilt", "Divisé", "Diviso", "Раздвоенный", "مقسوم", "Terbelah", "スプリット", "분할")
T("Candy", "Şeker", "Caramelo", "Doce", "Zuckerstange", "Bonbon", "Caramella", "Леденец", "حلوى", "Permen", "キャンディ", "캔디")

# ------------------------------------------------------------------ text motions (in / out)
T("None", "Yok", "Ninguno", "Nenhum", "Keine", "Aucun", "Nessuno", "Нет", "بلا", "Tidak ada", "なし", "없음")
T("Fade", "Solma", "Fundido", "Esmaecer", "Blende", "Fondu", "Dissolvenza", "Растворение", "تلاشٍ", "Pudar", "フェード", "페이드")
T("Pop", "Patla", "Pop", "Pop", "Pop", "Pop", "Pop", "Хлоп", "فرقعة", "Pop", "ポップ", "팝")
T("Bounce", "Zıpla", "Rebote", "Quicar", "Hüpfen", "Rebond", "Rimbalzo", "Отскок", "ارتداد", "Pantul", "バウンス", "바운스")
T("Zoom", "Yakınlaş", "Zoom", "Zoom", "Zoom", "Zoom", "Zoom", "Зум", "تكبير", "Zoom", "ズーム", "줌")
T("Slide up", "Yukarı kay", "Subir", "Subir", "Nach oben", "Vers le haut", "Su", "Вверх", "انزلاق لأعلى", "Geser ke atas",
  "上へスライド", "위로")
T("Slide down", "Aşağı kay", "Bajar", "Descer", "Nach unten", "Vers le bas", "Giù", "Вниз", "انزلاق لأسفل", "Geser ke bawah",
  "下へスライド", "아래로")
T("Slide left", "Sola kay", "A la izquierda", "Para a esquerda", "Nach links", "Vers la gauche", "A sinistra", "Влево",
  "انزلاق لليسار", "Geser ke kiri", "左へスライド", "왼쪽으로")
T("Slide right", "Sağa kay", "A la derecha", "Para a direita", "Nach rechts", "Vers la droite", "A destra", "Вправо",
  "انزلاق لليمين", "Geser ke kanan", "右へスライド", "오른쪽으로")
T("Typewriter", "Daktilo", "Máquina de escribir", "Máquina de escrever", "Schreibmaschine", "Machine à écrire", "Macchina da scrivere",
  "Печатная машинка", "آلة كاتبة", "Mesin ketik", "タイプライター", "타자기")
T("Rise", "Yüksel", "Ascenso", "Subida", "Aufsteigen", "Montée", "Salita", "Подъём", "صعود", "Naik", "ライズ", "떠오르기")
T("Drop in", "Düş", "Caída", "Queda", "Reinfallen", "Chute", "Caduta", "Падение", "سقوط", "Jatuh", "ドロップイン", "떨어지기")
T("Wave", "Dalga", "Ola", "Onda", "Welle", "Vague", "Onda", "Волна", "موجة", "Gelombang", "ウェーブ", "물결")
T("Jump", "Sıçra", "Salto", "Pulo", "Springen", "Saut", "Salto", "Прыжок", "قفز", "Lompat", "ジャンプ", "점프")
T("Shake", "Salla", "Temblor", "Tremer", "Wackeln", "Secousse", "Scossa", "Тряска", "اهتزاز", "Goyang", "シェイク", "흔들기")
T("Pulse", "Nabız", "Pulso", "Pulsar", "Puls", "Pulsation", "Pulsazione", "Пульс", "نبض", "Denyut", "パルス", "펄스")
T("Swing", "Sallan", "Balanceo", "Balanço", "Schaukeln", "Balancement", "Oscillazione", "Качание", "تأرجح", "Ayun", "スイング", "스윙")
T("Flicker", "Titreme", "Parpadeo", "Piscar", "Flackern", "Scintillement", "Sfarfallio", "Мерцание", "وميض", "Kedip", "点滅", "깜빡임")
T("Shrink", "Küçül", "Encoger", "Encolher", "Schrumpfen", "Rétrécir", "Rimpicciolisci", "Сжатие", "انكماش", "Mengecil", "縮小", "축소")
T("Blow up", "Patlat", "Explotar", "Explodir", "Aufblasen", "Exploser", "Esplodi", "Взрыв", "انفجار", "Meledak", "膨張", "터지기")
T("Erase", "Sil", "Borrar", "Apagar", "Radieren", "Effacer", "Cancella", "Стирание", "مسح", "Hapus", "消去", "지우기")
T("Fall", "Düş", "Caer", "Cair", "Fallen", "Tomber", "Cadi", "Падение вниз", "سقوط للأسفل", "Runtuh", "落下", "떨어뜨리기")
T("Scatter", "Dağıl", "Dispersar", "Espalhar", "Zerstreuen", "Disperser", "Disperdi", "Разлёт", "تبعثر", "Buyar", "散らばる", "흩어지기")

# ------------------------------------------------------------------ sound categories
T("Comedy", "Komedi", "Comedia", "Comédia", "Comedy", "Comédie", "Comico", "Комедия", "كوميديا", "Komedi", "コメディ", "코미디")
T("Drama", "Dram", "Drama", "Drama", "Drama", "Drame", "Dramma", "Драма", "دراما", "Drama", "ドラマ", "드라마")
T("Jingles", "Cıngıllar", "Jingles", "Vinhetas", "Jingles", "Jingles", "Jingle", "Джинглы", "فواصل موسيقية", "Jingle", "ジングル", "징글")
T("Reactions", "Tepkiler", "Reacciones", "Reações", "Reaktionen", "Réactions", "Reazioni", "Реакции", "ردود فعل", "Reaksi",
  "リアクション", "리액션")
T("Sale", "İndirim", "Ofertas", "Promoção", "Sale", "Soldes", "Saldi", "Распродажа", "تخفيضات", "Diskon", "セール", "세일")
T("Transitions", "Geçişler", "Transiciones", "Transições", "Übergänge", "Transitions", "Transizioni", "Переходы", "انتقالات",
  "Transisi", "トランジション", "전환")
T("Voice", "Ses kaydı", "Voz", "Voz", "Stimme", "Voix", "Voce", "Голос", "صوت بشري", "Suara orang", "ボイス", "목소리")

# ------------------------------------------------------------------ sound names (the spoken voice clips keep their English words)
T("Applause", "Alkış", "Aplausos", "Aplausos", "Applaus", "Applaudissements", "Applausi", "Аплодисменты", "تصفيق", "Tepuk tangan",
  "拍手", "박수")
T("Cheer", "Tezahürat", "Ovación", "Torcida", "Jubel", "Acclamations", "Ovazione", "Ликование", "هتاف", "Sorakan", "歓声", "환호")
T("Yay", "Yaşasın", "¡Bien!", "Eba", "Juhu", "Youpi", "Evviva", "Ура", "ياي", "Horee", "やったー", "야호")
T("Laugh", "Kahkaha", "Risas", "Risada", "Lachen", "Rires", "Risata", "Смех", "ضحك", "Tawa", "笑い声", "웃음")
T("Aww", "Ayy", "Oooh", "Own", "Ohhh", "Oooh", "Ooh", "Ах", "أوه", "Ooh", "あら〜", "아이고")
T("Boo", "Yuh", "Abucheo", "Vaia", "Buh", "Hou", "Buu", "Бу", "استهجان", "Huu", "ブーイング", "야유")
T("Gasp", "Şaşkınlık", "Asombro", "Suspiro", "Staunen", "Stupeur", "Stupore", "Ах!", "شهقة", "Terkesiap", "息をのむ", "헉")
T("Wow", "Vay", "Guau", "Uau", "Wow", "Waouh", "Wow", "Вау", "واو", "Wow", "ワオ", "와")
T("Ba dum tss", "Ba dum tss", "Ba dum tss", "Ba dum tss", "Ba dum tss", "Ba dum tss", "Ba dum tss", "Ба-дум-тсс", "با دم تس",
  "Ba dum tss", "ドンチャン", "바둠츠")
T("Sad trombone", "Hüzünlü trombon", "Trombón triste", "Trombone triste", "Traurige Posaune", "Trombone triste",
  "Trombone triste", "Грустный тромбон", "ترومبون حزين", "Trombon sedih", "残念トロンボーン", "슬픈 트롬본")
T("Record scratch", "Plak cızırtısı", "Rayón de disco", "Arranhão de disco", "Plattenkratzer", "Scratch de vinyle",
  "Graffio del disco", "Скретч пластинки", "خدش أسطوانة", "Goresan piringan", "レコードスクラッチ", "레코드 긁는 소리")
T("Slide whistle", "Kaydırmalı düdük", "Silbato de émbolo", "Apito de êmbolo", "Lotusflöte", "Sifflet à coulisse",
  "Fischietto a coulisse", "Свисток-слайд", "صافرة منزلقة", "Peluit geser", "スライドホイッスル", "슬라이드 휘슬")
T("Cartoon fall", "Çizgi film düşüşü", "Caída de dibujos", "Queda de desenho", "Cartoon-Sturz", "Chute de dessin animé",
  "Caduta da cartone", "Мультяшное падение", "سقوط كرتوني", "Jatuh kartun", "アニメの落下音", "만화 추락")
T("Boing", "Boing", "Boing", "Boing", "Boing", "Boing", "Boing", "Бойнг", "بوينغ", "Boing", "ボヨン", "뿅")
T("Kiss", "Öpücük", "Beso", "Beijo", "Kuss", "Bisou", "Bacio", "Поцелуй", "قبلة", "Cium", "キス", "뽀뽀")
T("Crickets", "Cırcır böceği", "Grillos", "Grilos", "Grillen", "Criquets", "Grilli", "Сверчки", "صراصير الليل", "Jangkrik",
  "コオロギ", "귀뚜라미")
T("Cha-ching", "Kasa sesi", "Caja registradora", "Caixa registradora", "Kasse", "Tiroir-caisse", "Registratore di cassa",
  "Касса", "صوت الخزينة", "Kaching", "チャリーン", "짤랑")
T("Air horn", "Korna", "Bocina", "Buzina", "Drucklufthorn", "Corne de brume", "Trombetta", "Гудок", "بوق", "Terompet udara",
  "エアホーン", "에어혼")
T("Drum roll", "Davul", "Redoble", "Rufar de tambores", "Trommelwirbel", "Roulement de tambour", "Rullo di tamburi",
  "Барабанная дробь", "قرع الطبول", "Gebukan drum", "ドラムロール", "드럼롤")
T("Ding", "Ding", "Ding", "Ding", "Ding", "Ding", "Ding", "Дзинь", "دينغ", "Ding", "チーン", "딩")
T("Ta-da", "Ta-da", "Tachán", "Tcharam", "Tadaa", "Tadaa", "Tadà", "Та-дам", "تادا", "Ta-da", "ジャジャーン", "짜잔")
T("Sparkle", "Pırıltı", "Destello", "Brilho", "Glitzern", "Scintillement", "Scintillio", "Блеск", "بريق", "Kilau", "キラキラ", "반짝")
T("Whoosh", "Vuuş", "Zas", "Vush", "Wusch", "Whoosh", "Whoosh", "Вжух", "ووش", "Wus", "シュッ", "휙")
T("Swoosh", "Hışırtı", "Zum", "Zum", "Sausen", "Swoosh", "Swoosh", "Свист", "سووش", "Syut", "ヒュッ", "쉭")
T("Dramatic", "Dramatik", "Dramático", "Dramático", "Dramatisch", "Dramatique", "Drammatico", "Драматично", "درامي", "Dramatis",
  "ドラマチック", "극적인")
T("Surprise", "Sürpriz", "Sorpresa", "Surpresa", "Überraschung", "Surprise", "Sorpresa", "Сюрприз", "مفاجأة", "Kejutan",
  "サプライズ", "놀람")
T("Explosion", "Patlama", "Explosión", "Explosão", "Explosion", "Explosion", "Esplosione", "Взрыв", "انفجار", "Ledakan", "爆発", "폭발")
T("Ticking", "Tik tak", "Tictac", "Tique-taque", "Ticken", "Tic-tac", "Ticchettio", "Тиканье", "تكتكة", "Detak jam", "チクタク", "째깍째깍")
T("Heartbeat", "Kalp atışı", "Latido", "Batimento", "Herzschlag", "Battement de cœur", "Battito", "Сердцебиение", "نبض القلب",
  "Detak jantung", "心臓の鼓動", "심장 박동")
T("Sax jingle", "Saksafon cıngılı", "Jingle de saxo", "Vinheta de sax", "Saxofon-Jingle", "Jingle de saxo", "Jingle di sax",
  "Саксофон", "لحن ساكسفون", "Jingle saksofon", "サックスジングル", "색소폰 징글")
T("Pizzicato", "Pizzicato", "Pizzicato", "Pizzicato", "Pizzicato", "Pizzicato", "Pizzicato", "Пиццикато", "بيتزيكاتو",
  "Pizzicato", "ピチカート", "피치카토")
T("Steel drums", "Çelik davul", "Tambores de acero", "Steel drum", "Steeldrums", "Steel drum", "Steel drum", "Стил-драм",
  "طبول معدنية", "Steel drum", "スチールドラム", "스틸 드럼")
T("Big finish", "Büyük final", "Gran final", "Grande final", "Großes Finale", "Grand final", "Gran finale", "Большой финал",
  "خاتمة كبيرة", "Akhir megah", "フィナーレ", "피날레")
T("8-bit win", "8-bit zafer", "Victoria 8 bits", "Vitória 8 bits", "8-Bit-Sieg", "Victoire 8 bits", "Vittoria 8 bit",
  "8-битная победа", "فوز 8 بت", "Menang 8-bit", "8ビット勝利", "8비트 승리")

# ------------------------------------------------------------------ sticker names
T("Tears of joy", "Gülmekten ağlayan", "Lágrimas de risa", "Chorando de rir", "Freudentränen", "Mort de rire", "Lacrime di gioia",
  "Слёзы радости", "دموع الفرح", "Tertawa terbahak", "嬉し泣き", "기쁨의 눈물")
T("ROFL", "Yerlere yatmak", "Muerto de risa", "Rolando de rir", "Am Boden vor Lachen", "Plié de rire", "Morto dal ridere",
  "Катаюсь от смеха", "أتدحرج ضحكاً", "Guling-guling", "笑い転げる", "빵 터짐")
T("Heart eyes", "Kalp gözlü", "Ojos de corazón", "Olhos de coração", "Herzaugen", "Yeux en cœur", "Occhi a cuore", "Влюблённый",
  "عيون القلب", "Mata hati", "ハートの目", "하트 눈")
T("Star struck", "Büyülenmiş", "Deslumbrado", "Deslumbrado", "Starstruck", "Ébloui", "Abbagliato", "Звёздный восторг", "منبهر",
  "Terpesona", "スター目", "반함")
T("Sunglasses", "Güneş gözlüklü", "Gafas de sol", "Óculos escuros", "Sonnenbrille", "Lunettes de soleil", "Occhiali da sole",
  "Очки", "نظارة شمسية", "Kacamata hitam", "サングラス", "선글라스")
T("Mind blown", "Beyin yandı", "Mente explotada", "Mente explodindo", "Kopf explodiert", "Esprit soufflé", "Mente esplosa",
  "Взрыв мозга", "مذهول", "Pikiran meledak", "頭爆発", "머리 터짐")
T("Scream", "Çığlık", "Grito", "Grito", "Schrei", "Cri", "Urlo", "Крик", "صراخ", "Menjerit", "叫び", "비명")
T("Party", "Parti", "Fiesta", "Festa", "Party", "Fête", "Festa", "Вечеринка", "حفلة", "Pesta", "パーティー", "파티")
T("Money mouth", "Para ağızlı", "Boca de dinero", "Boca de dinheiro", "Geldmund", "Bouche d'argent", "Bocca di soldi",
  "Деньги во рту", "فم المال", "Mulut uang", "お金の口", "돈 입")
T("Eye roll", "Göz devirme", "Ojos en blanco", "Revirar os olhos", "Augenrollen", "Yeux au ciel", "Occhi al cielo", "Закатил глаза",
  "لف العينين", "Memutar mata", "あきれ顔", "눈 굴리기")
T("Crying", "Ağlayan", "Llorando", "Chorando", "Weinen", "En pleurs", "Pianto", "Плач", "بكاء", "Menangis", "大泣き", "엉엉")
T("Angry", "Kızgın", "Enojado", "Bravo", "Wütend", "En colère", "Arrabbiato", "Злой", "غاضب", "Marah", "怒り", "화남")
T("Thinking", "Düşünen", "Pensando", "Pensando", "Nachdenklich", "Réflexion", "Pensieroso", "Думаю", "تفكير", "Berpikir", "考え中", "생각 중")
T("Smirk", "Sırıtma", "Sonrisa pícara", "Sorrisinho", "Grinsen", "Sourire en coin", "Sorrisetto", "Ухмылка", "ابتسامة ماكرة",
  "Senyum licik", "ニヤリ", "씨익")
T("Eyes", "Gözler", "Ojos", "Olhos", "Augen", "Yeux", "Occhi", "Глаза", "عيون", "Mata", "目", "눈")
T("Thumbs up", "Beğen", "Pulgar arriba", "Joinha", "Daumen hoch", "Pouce levé", "Pollice su", "Класс", "إعجاب", "Jempol",
  "いいね", "최고")
T("Clap", "Alkış", "Aplauso", "Palmas", "Klatschen", "Bravo", "Applauso", "Хлопки", "تصفيق", "Tepuk tangan", "拍手", "박수")
T("Hands up", "Eller havada", "Manos arriba", "Mãos para cima", "Hände hoch", "Mains levées", "Mani in alto", "Руки вверх",
  "الأيدي للأعلى", "Angkat tangan", "バンザイ", "만세")
T("Heart", "Kalp", "Corazón", "Coração", "Herz", "Cœur", "Cuore", "Сердце", "قلب", "Hati", "ハート", "하트")
T("100", "100", "100", "100", "100", "100", "100", "100", "100", "100", "100", "100")
T("Boom", "Bum", "Bum", "Bum", "Bumm", "Boum", "Bum", "Бум", "بوم", "Bum", "ドカン", "쾅")
T("Sparkles", "Parıltılar", "Destellos", "Brilhos", "Funkeln", "Étincelles", "Scintille", "Искры", "بريق", "Kilauan", "キラキラ", "반짝반짝")
T("Tada", "Tada", "Tachán", "Tcharam", "Tadaa", "Tadaa", "Tadà", "Та-дам", "تادا", "Tada", "ジャジャーン", "짜잔")
T("Money wings", "Uçan para", "Dinero volando", "Dinheiro voando", "Fliegendes Geld", "Argent qui s'envole", "Soldi che volano",
  "Деньги улетают", "مال طائر", "Uang terbang", "飛ぶお金", "날아가는 돈")
T("Rocket", "Roket", "Cohete", "Foguete", "Rakete", "Fusée", "Razzo", "Ракета", "صاروخ", "Roket", "ロケット", "로켓")
T("Star", "Yıldız", "Estrella", "Estrela", "Stern", "Étoile", "Stella", "Звезда", "نجمة", "Bintang", "星", "별")
T("Crown", "Taç", "Corona", "Coroa", "Krone", "Couronne", "Corona", "Корона", "تاج", "Mahkota", "王冠", "왕관")
T("Gem", "Mücevher", "Gema", "Joia", "Edelstein", "Joyau", "Gemma", "Бриллиант", "جوهرة", "Permata", "宝石", "보석")
T("Trophy", "Kupa", "Trofeo", "Troféu", "Pokal", "Trophée", "Trofeo", "Кубок", "كأس", "Piala", "トロフィー", "트로피")
T("Bullseye", "Tam isabet", "Diana", "Na mosca", "Volltreffer", "Dans le mille", "Centro", "В яблочко", "في الهدف", "Tepat sasaran",
  "的中", "명중")
T("Zap", "Şimşek", "Rayo", "Raio", "Blitz", "Éclair", "Fulmine", "Молния", "برق", "Petir", "稲妻", "번개")
T("Popcorn", "Patlamış mısır", "Palomitas", "Pipoca", "Popcorn", "Pop-corn", "Popcorn", "Попкорн", "فشار", "Popcorn", "ポップコーン", "팝콘")
T("Deal", "Anlaştık", "Trato hecho", "Fechado", "Deal", "Marché conclu", "Affare fatto", "Договорились", "اتفاق", "Sepakat",
  "取引成立", "거래 성사")
T("Heart hands", "Kalp eller", "Manos de corazón", "Mãos de coração", "Herzhände", "Mains en cœur", "Mani a cuore", "Сердце руками",
  "قلب باليدين", "Tangan hati", "ハートの手", "손하트")
T("Chef kiss", "Şef öpücüğü", "Beso del chef", "Beijo do chef", "Chefkuss", "Baiser du chef", "Bacio dello chef", "Пальчики оближешь",
  "قبلة الطاهي", "Ciuman koki", "シェフのキス", "셰프의 키스")
T("Strong", "Güçlü", "Fuerte", "Forte", "Stark", "Costaud", "Forte", "Сила", "قوي", "Kuat", "力こぶ", "힘")
T("Please", "Lütfen", "Por favor", "Por favor", "Bitte", "S'il te plaît", "Per favore", "Пожалуйста", "من فضلك", "Tolong", "お願い", "제발")
T("Sleepy", "Uykulu", "Con sueño", "Sonolento", "Müde", "Endormi", "Assonnato", "Сонный", "نعسان", "Mengantuk", "眠い", "졸림")
T("Clown", "Palyaço", "Payaso", "Palhaço", "Clown", "Clown", "Pagliaccio", "Клоун", "مهرج", "Badut", "ピエロ", "광대")
T("Ghost", "Hayalet", "Fantasma", "Fantasma", "Geist", "Fantôme", "Fantasma", "Призрак", "شبح", "Hantu", "おばけ", "유령")
T("Skull", "Kafatası", "Calavera", "Caveira", "Totenkopf", "Crâne", "Teschio", "Череп", "جمجمة", "Tengkorak", "ドクロ", "해골")
