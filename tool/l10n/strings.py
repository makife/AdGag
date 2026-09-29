# -*- coding: utf-8 -*-
"""AdGag UI strings in every supported language — THE source of truth.

Edit here, then run `python tool/l10n/build_arb.py` to regenerate
l10n/app_<lang>.arb, then `flutter gen-l10n`. Never hand-edit the .arb files.

Brand words stay the same in every language on purpose (owner's decision):
SOLD, GAG!, AD, AD THIS, REVIEWS, AdGag. Placeholders use {name}; declare
them in PLACEHOLDERS below.
"""

LANGS = ["en", "tr", "es", "pt", "de", "fr", "it", "ru", "ar", "id", "ja", "ko"]

# Shown in Settings > Language, in each language's own name.
LANGUAGE_NAMES = {
    "en": "English", "tr": "Türkçe", "es": "Español", "pt": "Português", "de": "Deutsch",
    "fr": "Français", "it": "Italiano", "ru": "Русский", "ar": "العربية", "id": "Bahasa Indonesia",
    "ja": "日本語", "ko": "한국어",
}

PLACEHOLDERS = {
    "accountDeleteConfirmHint": {"username": "String"},
    "accountDeleteFailed": {"error": "String"},
    "actionSoldCount": {"count": "String"},
    "dailyAdParticipants": {"count": "String"},
    "subjectAdCount": {"count": "String"},
    "settingsLogOut": {"username": "String"},
    "blockedUnblockConfirmTitle": {"username": "String"},
    "authCheckEmailBody": {"email": "String"},
    "blockFailed": {"error": "String"},
    "blockConfirmTitle": {"username": "String"},
    "blockDoneNamed": {"username": "String"},
    "deleteFailed": {"error": "String"},
    "reportFailed": {"error": "String"},
    "reviewsPostFailed": {"error": "String"},
    "avatarUploadFailed": {"error": "String"},
    "saveFailed": {"error": "String"},
    "cameraStartFailed": {"error": "String"},
    "cameraSwitchFailed": {"error": "String"},
    "importFailed": {"error": "String"},
    "createUploadingProgress": {"percent": "String"},
    "activityNewFollower": {"actor": "String"},
    "activityNewReview": {"actor": "String"},
    "activityAdThis": {"actor": "String"},
    "timeMinutesAgo": {"n": "String"},
    "timeHoursAgo": {"n": "String"},
    "timeDaysAgo": {"n": "String"},
    "usernameTooShort": {"min": "String"},
    "usernameTooLong": {"max": "String"},
    "shareMessage": {"subject": "String", "url": "String"},
    "shareMessageNoSubject": {"url": "String"},
}

S = {}


def K(key, en, tr, es, pt, de, fr, it, ru, ar, id_, ja, ko):
    S[key] = dict(en=en, tr=tr, es=es, pt=pt, de=de, fr=fr, it=it, ru=ru, ar=ar, id=id_, ja=ja, ko=ko)


def BRAND(key, text):
    """Same text in every language."""
    K(key, *([text] * 12))


# ---------------------------------------------------------------- brand
BRAND("appName", "AdGag")
BRAND("navAd", "AD")
BRAND("actionSold", "SOLD")
BRAND("actionReviews", "REVIEWS")
BRAND("actionShare", "GAG!")
BRAND("actionAdThis", "AD THIS")
K("actionSoldCount", "{count} SOLD", "{count} SOLD", "{count} SOLD", "{count} SOLD", "{count} SOLD", "{count} SOLD",
  "{count} SOLD", "{count} SOLD", "{count} SOLD", "{count} SOLD", "{count} SOLD", "{count} SOLD")

# ---------------------------------------------------------------- tagline
K("appTagline",
  "The social network where everything is an ad.",
  "Her şeyin reklam olduğu sosyal ağ.",
  "La red social donde todo es un anuncio.",
  "A rede social onde tudo é um anúncio.",
  "Das soziale Netzwerk, in dem alles Werbung ist.",
  "Le réseau social où tout est une pub.",
  "Il social network dove tutto è una pubblicità.",
  "Соцсеть, где всё — реклама.",
  "الشبكة الاجتماعية حيث كل شيء إعلان.",
  "Jejaring sosial tempat semuanya adalah iklan.",
  "すべてが広告になるSNS。",
  "모든 것이 광고가 되는 소셜 네트워크.")
K("appTaglineShort", "See it. Ad it. Go.", "Gör. Reklamını yap. Git.", "Míralo. Anúncialo. Ya.", "Viu. Anunciou. Pronto.",
  "Sehen. Bewerben. Los.", "Vois. Pubbe. Go.", "Guardalo. Pubblicizzalo. Vai.", "Увидел. Прорекламировал. Вперёд.",
  "شاهد. أعلن. انطلق.", "Lihat. Iklankan. Gas.", "見て、広告して、出す。", "보고, 광고하고, 올리기.")
K("onboardingSlogan", "The social network where everything is an ad.", "Her şeyin reklam olduğu sosyal ağ.",
  "La red social donde todo es un anuncio.", "A rede social onde tudo é um anúncio.",
  "Das soziale Netzwerk, in dem alles Werbung ist.", "Le réseau social où tout est une pub.",
  "Il social network dove tutto è una pubblicità.", "Соцсеть, где всё — реклама.",
  "الشبكة الاجتماعية حيث كل شيء إعلان.", "Jejaring sosial tempat semuanya adalah iklan.",
  "すべてが広告になるSNS。", "모든 것이 광고가 되는 소셜 네트워크.")

# ---------------------------------------------------------------- navigation
K("navHome", "Home", "Ana Sayfa", "Inicio", "Início", "Start", "Accueil", "Home", "Главная", "الرئيسية", "Beranda", "ホーム", "홈")
K("navMarket", "Market", "Pazar", "Mercado", "Mercado", "Markt", "Marché", "Mercato", "Рынок", "السوق", "Pasar", "マーケット", "마켓")
K("navActivity", "Activity", "Aktivite", "Actividad", "Atividade", "Aktivität", "Activité", "Attività", "Активность", "النشاط", "Aktivitas", "アクティビティ", "활동")
K("navProfile", "Profile", "Profil", "Perfil", "Perfil", "Profil", "Profil", "Profilo", "Профиль", "الملف الشخصي", "Profil", "プロフィール", "프로필")

# ---------------------------------------------------------------- common
K("genericRetry", "Retry", "Tekrar dene", "Reintentar", "Tentar de novo", "Erneut versuchen", "Réessayer", "Riprova", "Повторить", "إعادة المحاولة", "Coba lagi", "再試行", "다시 시도")
K("genericTryAgain", "Try again", "Tekrar dene", "Intentar de nuevo", "Tentar novamente", "Nochmal versuchen", "Réessayer", "Riprova", "Попробовать снова", "حاول مرة أخرى", "Coba lagi", "もう一度", "다시 시도")
K("genericCancel", "Cancel", "İptal", "Cancelar", "Cancelar", "Abbrechen", "Annuler", "Annulla", "Отмена", "إلغاء", "Batal", "キャンセル", "취소")
K("genericSave", "Save", "Kaydet", "Guardar", "Salvar", "Speichern", "Enregistrer", "Salva", "Сохранить", "حفظ", "Simpan", "保存", "저장")
K("genericDone", "Done", "Tamam", "Listo", "Concluído", "Fertig", "Terminé", "Fatto", "Готово", "تم", "Selesai", "完了", "완료")
K("genericNext", "Next", "İleri", "Siguiente", "Próximo", "Weiter", "Suivant", "Avanti", "Далее", "التالي", "Lanjut", "次へ", "다음")
K("genericDelete", "Delete", "Sil", "Eliminar", "Excluir", "Löschen", "Supprimer", "Elimina", "Удалить", "حذف", "Hapus", "削除", "삭제")
K("genericMore", "More", "Daha fazla", "Más", "Mais", "Mehr", "Plus", "Altro", "Ещё", "المزيد", "Lainnya", "その他", "더보기")
K("genericLoadFailed", "Couldn't load this.", "Yüklenemedi.", "No se pudo cargar.", "Não foi possível carregar.",
  "Konnte nicht geladen werden.", "Chargement impossible.", "Impossibile caricare.", "Не удалось загрузить.",
  "تعذّر التحميل.", "Gagal memuat.", "読み込めませんでした。", "불러오지 못했어요.")
K("genericOffline", "You're offline. Some content may be unavailable.", "Çevrimdışısın. Bazı içerikler kullanılamayabilir.",
  "Sin conexión. Parte del contenido no está disponible.", "Você está offline. Alguns conteúdos podem não estar disponíveis.",
  "Du bist offline. Manche Inhalte sind nicht verfügbar.", "Hors ligne. Certains contenus sont indisponibles.",
  "Sei offline. Alcuni contenuti potrebbero non essere disponibili.", "Нет сети. Часть контента может быть недоступна.",
  "أنت غير متصل. قد لا يتوفر بعض المحتوى.", "Kamu sedang offline. Sebagian konten mungkin tidak tersedia.",
  "オフラインです。一部のコンテンツは表示できません。", "오프라인이에요. 일부 콘텐츠를 볼 수 없어요.")
K("unknownUser", "unknown", "bilinmiyor", "desconocido", "desconhecido", "unbekannt", "inconnu", "sconosciuto", "неизвестно",
  "غير معروف", "tidak dikenal", "不明", "알 수 없음")

# ---------------------------------------------------------------- onboarding
K("onboardingPickAnything", "Pick anything.", "Bir şey seç.", "Elige cualquier cosa.", "Escolha qualquer coisa.",
  "Such dir was aus.", "Choisis n'importe quoi.", "Scegli qualsiasi cosa.", "Выбери что угодно.", "اختر أي شيء.",
  "Pilih apa saja.", "何でも選んで。", "무엇이든 골라요.")
K("onboardingPickAnythingBody", "A rock. Your coffee. Yourself. Monday.", "Bir taş. Kahven. Kendin. Pazartesi.",
  "Una piedra. Tu café. Tú. El lunes.", "Uma pedra. Seu café. Você. Segunda-feira.", "Ein Stein. Dein Kaffee. Du selbst. Montag.",
  "Un caillou. Ton café. Toi. Le lundi.", "Un sasso. Il tuo caffè. Te stesso. Il lunedì.", "Камень. Твой кофе. Ты сам. Понедельник.",
  "حجر. قهوتك. نفسك. يوم الاثنين.", "Sebuah batu. Kopimu. Dirimu. Hari Senin.", "石ころ。コーヒー。自分自身。月曜日。",
  "돌멩이. 네 커피. 너 자신. 월요일.")
K("onboardingSellIt", "Sell it in 30 seconds.", "30 saniyede sat.", "Véndelo en 30 segundos.", "Venda em 30 segundos.",
  "Verkauf es in 30 Sekunden.", "Vends-le en 30 secondes.", "Vendilo in 30 secondi.", "Продай за 30 секунд.",
  "بِعه في 30 ثانية.", "Jual dalam 30 detik.", "30秒で売り込め。", "30초 만에 팔아 봐요.")
K("onboardingSellItBody", "Short, punchy, funny. That's the format.", "Kısa, vurucu, komik. Format bu.",
  "Corto, directo, divertido. Ese es el formato.", "Curto, marcante, engraçado. Esse é o formato.",
  "Kurz, knackig, lustig. Das ist das Format.", "Court, percutant, drôle. C'est le format.",
  "Breve, incisivo, divertente. Questo è il formato.", "Коротко, ярко, смешно. Вот и весь формат.",
  "قصير، مؤثر، مضحك. هذا هو الأسلوب.", "Singkat, nendang, lucu. Itu formatnya.", "短く、強く、おもしろく。それがルール。",
  "짧고, 강렬하고, 웃기게. 그게 포맷이에요.")
K("onboardingSeeItAdIt", "See it. Ad it. Go.", "Gör. Reklamını yap. Git.", "Míralo. Anúncialo. Ya.", "Viu. Anunciou. Pronto.",
  "Sehen. Bewerben. Los.", "Vois. Pubbe. Go.", "Guardalo. Pubblicizzalo. Vai.", "Увидел. Прорекламировал. Вперёд.",
  "شاهد. أعلن. انطلق.", "Lihat. Iklankan. Gas.", "見て、広告して、出す。", "보고, 광고하고, 올리기.")
K("onboardingSeeItAdItBody", "Watch an ad. Make a better one. Publish.", "Bir reklam izle. Daha iyisini yap. Yayınla.",
  "Mira un anuncio. Haz uno mejor. Publícalo.", "Assista a um anúncio. Faça um melhor. Publique.",
  "Schau eine Werbung. Mach eine bessere. Veröffentliche sie.", "Regarde une pub. Fais mieux. Publie.",
  "Guarda una pubblicità. Fanne una migliore. Pubblicala.", "Посмотри рекламу. Сделай лучше. Опубликуй.",
  "شاهد إعلانًا. اصنع أفضل منه. انشره.", "Tonton iklan. Buat yang lebih bagus. Terbitkan.",
  "広告を見て、もっといいのを作って、公開しよう。", "광고를 보고, 더 잘 만들어서, 올려요.")
K("onboardingGetStarted", "Get started", "Başla", "Empezar", "Começar", "Los geht's", "Commencer", "Inizia", "Начать", "ابدأ", "Mulai", "はじめる", "시작하기")
K("onboardingSkip", "Skip", "Geç", "Omitir", "Pular", "Überspringen", "Passer", "Salta", "Пропустить", "تخطَّ", "Lewati", "スキップ", "건너뛰기")

# ---------------------------------------------------------------- auth
K("authSignInWithApple", "Continue with Apple", "Apple ile devam et", "Continuar con Apple", "Continuar com Apple",
  "Mit Apple fortfahren", "Continuer avec Apple", "Continua con Apple", "Продолжить с Apple", "المتابعة باستخدام Apple",
  "Lanjutkan dengan Apple", "Appleで続ける", "Apple로 계속하기")
K("authSignInWithGoogle", "Continue with Google", "Google ile devam et", "Continuar con Google", "Continuar com Google",
  "Mit Google fortfahren", "Continuer avec Google", "Continua con Google", "Продолжить с Google", "المتابعة باستخدام Google",
  "Lanjutkan dengan Google", "Googleで続ける", "Google로 계속하기")
K("authSignInWithEmail", "Continue with email", "E-posta ile devam et", "Continuar con email", "Continuar com e-mail",
  "Mit E-Mail fortfahren", "Continuer avec l'e-mail", "Continua con email", "Продолжить с email", "المتابعة بالبريد الإلكتروني",
  "Lanjutkan dengan email", "メールで続ける", "이메일로 계속하기")
K("authEmailLabel", "Email", "E-posta", "Email", "E-mail", "E-Mail", "E-mail", "Email", "Email", "البريد الإلكتروني", "Email", "メールアドレス", "이메일")
K("authPasswordLabel", "Password", "Şifre", "Contraseña", "Senha", "Passwort", "Mot de passe", "Password", "Пароль", "كلمة المرور", "Kata sandi", "パスワード", "비밀번호")
K("authUsernameLabel", "Username", "Kullanıcı adı", "Nombre de usuario", "Nome de usuário", "Benutzername", "Nom d'utilisateur",
  "Nome utente", "Имя пользователя", "اسم المستخدم", "Nama pengguna", "ユーザー名", "사용자 이름")
K("authSignIn", "Sign in", "Giriş yap", "Iniciar sesión", "Entrar", "Anmelden", "Se connecter", "Accedi", "Войти", "تسجيل الدخول", "Masuk", "ログイン", "로그인")
K("authSignUp", "Create account", "Hesap oluştur", "Crear cuenta", "Criar conta", "Konto erstellen", "Créer un compte", "Crea account",
  "Создать аккаунт", "إنشاء حساب", "Buat akun", "アカウント作成", "계정 만들기")
K("authNoAccount", "Need an account? Create one", "Hesabın yok mu? Oluştur", "¿No tienes cuenta? Crea una", "Não tem conta? Crie uma",
  "Noch kein Konto? Jetzt erstellen", "Pas de compte ? Crées-en un", "Non hai un account? Creane uno", "Нет аккаунта? Создайте",
  "ليس لديك حساب؟ أنشئ واحدًا", "Belum punya akun? Buat sekarang", "アカウントがない？作成する", "계정이 없나요? 만들기")
K("authHaveAccount", "Already have an account? Sign in", "Zaten hesabın var mı? Giriş yap", "¿Ya tienes cuenta? Inicia sesión",
  "Já tem conta? Entre", "Schon ein Konto? Anmelden", "Déjà un compte ? Connecte-toi", "Hai già un account? Accedi",
  "Уже есть аккаунт? Войти", "لديك حساب بالفعل؟ سجّل الدخول", "Sudah punya akun? Masuk", "アカウントをお持ちですか？ログイン",
  "이미 계정이 있나요? 로그인")
K("authInvalidEmail", "Enter a valid email", "Geçerli bir e-posta gir", "Introduce un email válido", "Digite um e-mail válido",
  "Gib eine gültige E-Mail ein", "Saisis un e-mail valide", "Inserisci un'email valida", "Введите корректный email",
  "أدخل بريدًا إلكترونيًا صالحًا", "Masukkan email yang valid", "有効なメールアドレスを入力してください", "올바른 이메일을 입력하세요")
K("authGenericError", "Something went wrong. Please try again.", "Bir şeyler ters gitti. Lütfen tekrar dene.",
  "Algo salió mal. Inténtalo de nuevo.", "Algo deu errado. Tente novamente.", "Etwas ist schiefgelaufen. Bitte versuch es erneut.",
  "Une erreur s'est produite. Réessaie.", "Qualcosa è andato storto. Riprova.", "Что-то пошло не так. Попробуйте ещё раз.",
  "حدث خطأ ما. حاول مرة أخرى.", "Terjadi kesalahan. Coba lagi.", "問題が発生しました。もう一度お試しください。",
  "문제가 발생했어요. 다시 시도해 주세요.")
K("authCheckEmailTitle", "Check your email", "E-postanı kontrol et", "Revisa tu email", "Verifique seu e-mail", "Schau in deine E-Mails",
  "Vérifie tes e-mails", "Controlla la tua email", "Проверьте почту", "تحقق من بريدك", "Cek email kamu", "メールを確認してください",
  "이메일을 확인하세요")
K("authCheckEmailBody",
  "We sent a confirmation link to {email}. Open it to activate your account, then sign in.",
  "{email} adresine bir onay bağlantısı gönderdik. Hesabını etkinleştirmek için bağlantıyı aç, sonra giriş yap.",
  "Enviamos un enlace de confirmación a {email}. Ábrelo para activar tu cuenta y luego inicia sesión.",
  "Enviamos um link de confirmação para {email}. Abra-o para ativar sua conta e depois entre.",
  "Wir haben einen Bestätigungslink an {email} geschickt. Öffne ihn, um dein Konto zu aktivieren, und melde dich dann an.",
  "Nous avons envoyé un lien de confirmation à {email}. Ouvre-le pour activer ton compte, puis connecte-toi.",
  "Abbiamo inviato un link di conferma a {email}. Aprilo per attivare l'account, poi accedi.",
  "Мы отправили ссылку для подтверждения на {email}. Откройте её, чтобы активировать аккаунт, затем войдите.",
  "أرسلنا رابط تأكيد إلى {email}. افتحه لتفعيل حسابك، ثم سجّل الدخول.",
  "Kami mengirim tautan konfirmasi ke {email}. Buka tautan itu untuk mengaktifkan akun, lalu masuk.",
  "{email} に確認リンクを送りました。リンクを開いてアカウントを有効にしてから、ログインしてください。",
  "{email}(으)로 확인 링크를 보냈어요. 링크를 열어 계정을 활성화한 뒤 로그인하세요.")
K("authCheckSpam", "Can't find it? Check your spam folder.", "Bulamadın mı? Spam klasörüne bak.",
  "¿No lo encuentras? Revisa la carpeta de spam.", "Não encontrou? Verifique a pasta de spam.",
  "Nicht gefunden? Schau im Spam-Ordner nach.", "Introuvable ? Regarde dans tes spams.",
  "Non la trovi? Controlla lo spam.", "Не нашли? Проверьте папку «Спам».", "لم تجده؟ تحقق من مجلد الرسائل غير المرغوب فيها.",
  "Tidak ketemu? Cek folder spam.", "見つからない場合は迷惑メールフォルダを確認してください。", "찾을 수 없나요? 스팸함을 확인하세요.")
K("authGoToSignIn", "Go to sign in", "Girişe git", "Ir a iniciar sesión", "Ir para o login", "Zur Anmeldung", "Aller à la connexion",
  "Vai all'accesso", "Перейти ко входу", "الانتقال إلى تسجيل الدخول", "Ke halaman masuk", "ログインへ", "로그인으로 이동")
K("authEmailTaken", "An account with this email already exists. Sign in instead.",
  "Bu e-postayla bir hesap zaten var. Giriş yap.", "Ya existe una cuenta con este email. Inicia sesión.",
  "Já existe uma conta com este e-mail. Entre.", "Mit dieser E-Mail gibt es schon ein Konto. Melde dich an.",
  "Un compte existe déjà avec cet e-mail. Connecte-toi.", "Esiste già un account con questa email. Accedi.",
  "Аккаунт с этим email уже есть. Войдите.", "يوجد حساب بهذا البريد بالفعل. سجّل الدخول.",
  "Akun dengan email ini sudah ada. Silakan masuk.", "このメールアドレスのアカウントは既にあります。ログインしてください。",
  "이 이메일로 된 계정이 이미 있어요. 로그인하세요.")
K("authUsernameTaken", "That username is taken. Try another one.", "Bu kullanıcı adı alınmış. Başka bir tane dene.",
  "Ese nombre de usuario ya existe. Prueba otro.", "Esse nome de usuário já existe. Tente outro.",
  "Dieser Benutzername ist vergeben. Versuch einen anderen.", "Ce nom d'utilisateur est pris. Essaie un autre.",
  "Nome utente già in uso. Provane un altro.", "Это имя занято. Попробуйте другое.", "اسم المستخدم هذا مأخوذ. جرّب اسمًا آخر.",
  "Nama pengguna itu sudah dipakai. Coba yang lain.", "このユーザー名は使われています。別の名前を試してください。",
  "이미 사용 중인 사용자 이름이에요. 다른 이름을 써 보세요.")
K("authEmailNotConfirmed", "Confirm your email first — check your inbox for the link.",
  "Önce e-postanı onayla — gelen kutundaki bağlantıya tıkla.", "Confirma tu email primero: busca el enlace en tu bandeja.",
  "Confirme seu e-mail primeiro: procure o link na sua caixa de entrada.", "Bestätige zuerst deine E-Mail – der Link ist in deinem Postfach.",
  "Confirme d'abord ton e-mail : le lien est dans ta boîte de réception.", "Conferma prima la tua email: trovi il link nella posta.",
  "Сначала подтвердите email — ссылка во входящих.", "أكّد بريدك أولًا — تجد الرابط في صندوق الوارد.",
  "Konfirmasi email kamu dulu — cek tautannya di kotak masuk.", "先にメールアドレスを確認してください。受信トレイのリンクを開いてください。",
  "먼저 이메일을 인증하세요. 받은편지함의 링크를 확인하세요.")
K("authWrongCredentials", "Wrong email or password.", "E-posta ya da şifre hatalı.", "Email o contraseña incorrectos.",
  "E-mail ou senha incorretos.", "E-Mail oder Passwort falsch.", "E-mail ou mot de passe incorrect.", "Email o password errati.",
  "Неверный email или пароль.", "البريد الإلكتروني أو كلمة المرور غير صحيحة.", "Email atau kata sandi salah.",
  "メールアドレスまたはパスワードが違います。", "이메일 또는 비밀번호가 틀렸어요.")
K("usernameTooShort", "Username must be at least {min} characters.", "Kullanıcı adı en az {min} karakter olmalı.",
  "El nombre de usuario debe tener al menos {min} caracteres.", "O nome de usuário deve ter pelo menos {min} caracteres.",
  "Der Benutzername muss mindestens {min} Zeichen haben.", "Le nom d'utilisateur doit contenir au moins {min} caractères.",
  "Il nome utente deve avere almeno {min} caratteri.", "Имя должно быть не короче {min} символов.",
  "يجب أن يتكون اسم المستخدم من {min} أحرف على الأقل.", "Nama pengguna minimal {min} karakter.",
  "ユーザー名は{min}文字以上にしてください。", "사용자 이름은 {min}자 이상이어야 해요.")
K("usernameTooLong", "Username must be at most {max} characters.", "Kullanıcı adı en fazla {max} karakter olabilir.",
  "El nombre de usuario puede tener como máximo {max} caracteres.", "O nome de usuário pode ter no máximo {max} caracteres.",
  "Der Benutzername darf höchstens {max} Zeichen haben.", "Le nom d'utilisateur ne peut pas dépasser {max} caractères.",
  "Il nome utente può avere al massimo {max} caratteri.", "Имя должно быть не длиннее {max} символов.",
  "يجب ألا يزيد اسم المستخدم عن {max} حرفًا.", "Nama pengguna maksimal {max} karakter.",
  "ユーザー名は{max}文字以内にしてください。", "사용자 이름은 {max}자 이하여야 해요.")
K("usernameStartLetter", "Username must start with a letter.", "Kullanıcı adı bir harfle başlamalı.",
  "El nombre de usuario debe empezar con una letra.", "O nome de usuário deve começar com uma letra.",
  "Der Benutzername muss mit einem Buchstaben beginnen.", "Le nom d'utilisateur doit commencer par une lettre.",
  "Il nome utente deve iniziare con una lettera.", "Имя должно начинаться с буквы.", "يجب أن يبدأ اسم المستخدم بحرف.",
  "Nama pengguna harus diawali huruf.", "ユーザー名は英字で始めてください。", "사용자 이름은 영문자로 시작해야 해요.")
K("usernameChars", "Only lowercase letters, numbers and underscores.", "Yalnızca küçük harf, rakam ve alt çizgi.",
  "Solo minúsculas, números y guiones bajos.", "Somente letras minúsculas, números e sublinhados.",
  "Nur Kleinbuchstaben, Zahlen und Unterstriche.", "Uniquement minuscules, chiffres et tirets bas.",
  "Solo lettere minuscole, numeri e trattini bassi.", "Только строчные латинские буквы, цифры и подчёркивания.",
  "أحرف لاتينية صغيرة وأرقام وشرطات سفلية فقط.", "Hanya huruf kecil, angka, dan garis bawah.",
  "小文字の英字・数字・アンダースコアのみ使えます。", "영문 소문자, 숫자, 밑줄만 쓸 수 있어요.")

# ---------------------------------------------------------------- feed / reactions
K("actionFollow", "FOLLOW", "TAKİP ET", "SEGUIR", "SEGUIR", "FOLGEN", "SUIVRE", "SEGUI", "ПОДПИСАТЬСЯ", "متابعة", "IKUTI", "フォロー", "팔로우")
K("actionFollowing", "FOLLOWING", "TAKİPTE", "SIGUIENDO", "SEGUINDO", "GEFOLGT", "ABONNÉ", "SEGUITO", "ПОДПИСКА", "تتابعه", "MENGIKUTI", "フォロー中", "팔로잉")
K("feedAdThisHint", "Think you can do better? Try AD THIS.", "Daha iyisini yapabilir misin? AD THIS'e bas.",
  "¿Crees que lo harías mejor? Prueba AD THIS.", "Acha que faz melhor? Experimente AD THIS.",
  "Kannst du das besser? Probier AD THIS.", "Tu peux faire mieux ? Essaie AD THIS.", "Pensi di fare di meglio? Prova AD THIS.",
  "Сможете лучше? Жмите AD THIS.", "تظن أنك تستطيع أفضل؟ جرّب AD THIS.", "Bisa bikin lebih bagus? Coba AD THIS.",
  "もっといいのが作れる？AD THISを押そう。", "더 잘 만들 수 있다고요? AD THIS를 눌러 보세요.")
K("feedRefreshFailed", "Couldn't refresh the feed.", "Akış yenilenemedi.", "No se pudo actualizar el feed.", "Não foi possível atualizar o feed.",
  "Feed konnte nicht aktualisiert werden.", "Impossible d'actualiser le fil.", "Impossibile aggiornare il feed.", "Не удалось обновить ленту.",
  "تعذّر تحديث الخلاصة.", "Gagal memuat ulang feed.", "フィードを更新できませんでした。", "피드를 새로고침하지 못했어요.")
K("feedLoadFailed", "Couldn't load the feed.", "Akış yüklenemedi.", "No se pudo cargar el feed.", "Não foi possível carregar o feed.",
  "Feed konnte nicht geladen werden.", "Impossible de charger le fil.", "Impossibile caricare il feed.", "Не удалось загрузить ленту.",
  "تعذّر تحميل الخلاصة.", "Gagal memuat feed.", "フィードを読み込めませんでした。", "피드를 불러오지 못했어요.")
K("feedEmptyTitle", "No one's sold anything yet.", "Henüz kimse bir şey satmadı.", "Nadie ha vendido nada todavía.",
  "Ninguém vendeu nada ainda.", "Noch hat niemand etwas verkauft.", "Personne n'a encore rien vendu.", "Nessuno ha ancora venduto niente.",
  "Никто ещё ничего не продал.", "لم يبِع أحد أي شيء بعد.", "Belum ada yang menjual apa pun.", "まだ誰も何も売っていません。",
  "아직 아무도 팔지 않았어요.")
K("feedEmptyBody", "Be the first to advertise something.", "Bir şeyin reklamını ilk yapan sen ol.", "Sé el primero en anunciar algo.",
  "Seja o primeiro a anunciar algo.", "Mach als Erste·r Werbung für etwas.", "Sois le premier à faire la pub de quelque chose.",
  "Sii il primo a pubblicizzare qualcosa.", "Прорекламируйте что-нибудь первым.", "كن أول من يعلن عن شيء.",
  "Jadilah yang pertama mengiklankan sesuatu.", "最初の広告を作ろう。", "첫 광고의 주인공이 되어 보세요.")
K("soldUpdateFailed", "Couldn't update SOLD right now.", "SOLD şu an güncellenemedi.", "No se pudo actualizar SOLD ahora.",
  "Não foi possível atualizar SOLD agora.", "SOLD konnte gerade nicht aktualisiert werden.", "Impossible de mettre à jour SOLD pour l'instant.",
  "Impossibile aggiornare SOLD ora.", "Не удалось обновить SOLD.", "تعذّر تحديث SOLD الآن.", "Tidak bisa memperbarui SOLD sekarang.",
  "今はSOLDを更新できません。", "지금은 SOLD를 업데이트할 수 없어요.")
K("soldRemove", "Remove SOLD", "SOLD'u kaldır", "Quitar SOLD", "Remover SOLD", "SOLD entfernen", "Retirer SOLD", "Rimuovi SOLD",
  "Убрать SOLD", "إزالة SOLD", "Hapus SOLD", "SOLDを取り消す", "SOLD 취소")
K("followUpdateFailed", "Couldn't update follow right now.", "Takip şu an güncellenemedi.", "No se pudo actualizar el seguimiento.",
  "Não foi possível atualizar o seguir agora.", "Folgen konnte gerade nicht aktualisiert werden.", "Impossible de mettre à jour l'abonnement.",
  "Impossibile aggiornare il segui ora.", "Не удалось изменить подписку.", "تعذّر تحديث المتابعة الآن.", "Tidak bisa memperbarui ikuti sekarang.",
  "今はフォローを更新できません。", "지금은 팔로우를 업데이트할 수 없어요.")
K("shareMessage", "{subject} on AdGag: {url}", "{subject} AdGag'de: {url}", "{subject} en AdGag: {url}", "{subject} no AdGag: {url}",
  "{subject} auf AdGag: {url}", "{subject} sur AdGag : {url}", "{subject} su AdGag: {url}", "{subject} в AdGag: {url}",
  "{subject} على AdGag: {url}", "{subject} di AdGag: {url}", "AdGagの{subject}: {url}", "AdGag의 {subject}: {url}")
K("shareMessageNoSubject", "On AdGag: {url}", "AdGag'de: {url}", "En AdGag: {url}", "No AdGag: {url}", "Auf AdGag: {url}",
  "Sur AdGag : {url}", "Su AdGag: {url}", "В AdGag: {url}", "على AdGag: {url}", "Di AdGag: {url}", "AdGagで見る: {url}", "AdGag에서 보기: {url}")

# ---------------------------------------------------------------- reviews
K("reviewsClose", "Close reviews", "Yorumları kapat", "Cerrar reseñas", "Fechar avaliações", "Bewertungen schließen", "Fermer les avis",
  "Chiudi recensioni", "Закрыть отзывы", "إغلاق التعليقات", "Tutup ulasan", "レビューを閉じる", "리뷰 닫기")
K("reviewsEmpty", "No reviews yet.", "Henüz yorum yok.", "Aún no hay reseñas.", "Ainda não há avaliações.", "Noch keine Bewertungen.",
  "Pas encore d'avis.", "Ancora nessuna recensione.", "Отзывов пока нет.", "لا توجد تعليقات بعد.", "Belum ada ulasan.", "まだレビューはありません。",
  "아직 리뷰가 없어요.")
K("reviewsHint", "Add a review…", "Yorum ekle…", "Escribe una reseña…", "Escreva uma avaliação…", "Bewertung schreiben…", "Ajoute un avis…",
  "Scrivi una recensione…", "Оставьте отзыв…", "أضف تعليقًا…", "Tulis ulasan…", "レビューを書く…", "리뷰 남기기…")
K("reviewsPostFailed", "Couldn't post: {error}", "Gönderilemedi: {error}", "No se pudo publicar: {error}", "Não foi possível publicar: {error}",
  "Konnte nicht gesendet werden: {error}", "Envoi impossible : {error}", "Impossibile pubblicare: {error}", "Не удалось отправить: {error}",
  "تعذّر النشر: {error}", "Gagal mengirim: {error}", "投稿できませんでした: {error}", "게시하지 못했어요: {error}")

# ---------------------------------------------------------------- more menu / moderation
K("reportAd", "Report", "Şikayet et", "Denunciar", "Denunciar", "Melden", "Signaler", "Segnala", "Пожаловаться", "إبلاغ", "Laporkan", "報告", "신고")
K("blockUser", "Block", "Engelle", "Bloquear", "Bloquear", "Blockieren", "Bloquer", "Blocca", "Заблокировать", "حظر", "Blokir", "ブロック", "차단")
K("blockDone", "Blocked.", "Engellendi.", "Bloqueado.", "Bloqueado.", "Blockiert.", "Bloqué.", "Bloccato.", "Заблокировано.", "تم الحظر.", "Diblokir.", "ブロックしました。", "차단했어요.")
K("blockConfirmTitle", "Block @{username}?", "@{username} engellensin mi?", "¿Bloquear a @{username}?", "Bloquear @{username}?",
  "@{username} blockieren?", "Bloquer @{username} ?", "Bloccare @{username}?", "Заблокировать @{username}?", "حظر @{username}؟",
  "Blokir @{username}?", "@{username}さんをブロックしますか？", "@{username}님을 차단할까요?")
K("blockConfirmNote", "Their Ads and reviews will disappear for you, and they won't be able to see yours. They won't be notified. You can unblock them any time in Settings.",
  "Reklamları ve yorumları sana görünmez, o da seninkileri göremez. Bundan haberi olmaz. Engeli istediğin zaman Ayarlar'dan kaldırabilirsin.",
  "Sus anuncios y reseñas desaparecerán para ti, y no podrá ver los tuyos. No recibirá ningún aviso. Puedes desbloquearlo cuando quieras en Ajustes.",
  "Os anúncios e avaliações dessa pessoa vão sumir para você, e ela não poderá ver os seus. Ela não será avisada. Você pode desbloquear quando quiser em Configurações.",
  "Seine Werbungen und Bewertungen verschwinden für dich, und er kann deine nicht sehen. Er wird nicht benachrichtigt. Du kannst die Blockierung jederzeit in den Einstellungen aufheben.",
  "Ses pubs et avis disparaîtront pour toi, et il ne pourra pas voir les tiens. Il ne sera pas prévenu. Tu peux le débloquer à tout moment dans les Réglages.",
  "Le sue pubblicità e recensioni spariranno per te e non potrà vedere le tue. Non riceverà alcun avviso. Puoi sbloccarlo quando vuoi nelle Impostazioni.",
  "Его реклама и отзывы исчезнут для вас, а он не увидит ваши. Он не получит уведомления. Разблокировать можно в любой момент в настройках.",
  "ستختفي إعلاناته ومراجعاته عنك، ولن يتمكن من رؤية إعلاناتك. لن يتم إشعاره. يمكنك إلغاء الحظر في أي وقت من الإعدادات.",
  "Iklan dan ulasannya akan hilang untukmu, dan dia tidak bisa melihat milikmu. Dia tidak akan diberi tahu. Kamu bisa membuka blokir kapan saja di Pengaturan.",
  "相手の広告とレビューが表示されなくなり、相手もあなたの広告を見られなくなります。相手に通知はされません。ブロックは設定からいつでも解除できます。",
  "그 사람의 광고와 리뷰가 보이지 않게 되고, 그 사람도 내 광고를 볼 수 없어요. 상대에게 알림은 가지 않아요. 차단은 설정에서 언제든 해제할 수 있어요.")
K("blockDoneNamed", "@{username} blocked", "@{username} engellendi", "@{username} bloqueado", "@{username} bloqueado", "@{username} blockiert",
  "@{username} bloqué", "@{username} bloccato", "@{username} заблокирован", "تم حظر @{username}", "@{username} diblokir",
  "@{username}さんをブロックしました", "@{username}님을 차단했어요")
K("blockUndo", "Undo", "Geri al", "Deshacer", "Desfazer", "Rückgängig", "Annuler", "Annulla", "Отменить", "تراجع", "Urungkan", "元に戻す", "실행 취소")
K("unblockDone", "Unblocked", "Engel kaldırıldı", "Desbloqueado", "Desbloqueado", "Blockierung aufgehoben", "Débloqué", "Sbloccato",
  "Разблокировано", "تم إلغاء الحظر", "Blokir dibuka", "ブロックを解除しました", "차단을 해제했어요")
K("profileBlockedNote", "You blocked this account. You won't see their Ads.", "Bu hesabı engelledin. Reklamlarını görmezsin.",
  "Bloqueaste esta cuenta. No verás sus anuncios.", "Você bloqueou esta conta. Não verá os anúncios dela.",
  "Du hast dieses Konto blockiert. Du siehst seine Werbungen nicht.", "Tu as bloqué ce compte. Tu ne verras pas ses pubs.",
  "Hai bloccato questo account. Non vedrai le sue pubblicità.", "Вы заблокировали этот аккаунт. Его реклама вам не показывается.",
  "لقد حظرت هذا الحساب. لن ترى إعلاناته.", "Kamu memblokir akun ini. Kamu tidak akan melihat iklannya.",
  "このアカウントをブロックしています。広告は表示されません。", "이 계정을 차단했어요. 광고가 보이지 않아요.")
K("blockFailed", "Couldn't block: {error}", "Engellenemedi: {error}", "No se pudo bloquear: {error}", "Não foi possível bloquear: {error}",
  "Blockieren fehlgeschlagen: {error}", "Blocage impossible : {error}", "Impossibile bloccare: {error}", "Не удалось заблокировать: {error}",
  "تعذّر الحظر: {error}", "Gagal memblokir: {error}", "ブロックできませんでした: {error}", "차단하지 못했어요: {error}")
K("deleteAdTitle", "Delete this Ad?", "Bu reklam silinsin mi?", "¿Eliminar este anuncio?", "Excluir este anúncio?", "Diese Werbung löschen?",
  "Supprimer cette pub ?", "Eliminare questa pubblicità?", "Удалить эту рекламу?", "حذف هذا الإعلان؟", "Hapus iklan ini?", "この広告を削除しますか？",
  "이 광고를 삭제할까요?")
K("deleteAdBody", "This can't be undone. It will be removed from feeds immediately.", "Bu geri alınamaz. Reklam akıştan hemen kaldırılır.",
  "No se puede deshacer. Se quitará de los feeds al instante.", "Não pode ser desfeito. Será removido dos feeds imediatamente.",
  "Das lässt sich nicht rückgängig machen. Sie verschwindet sofort aus den Feeds.", "Action irréversible. Elle disparaîtra immédiatement des fils.",
  "L'azione è irreversibile. Verrà rimossa subito dai feed.", "Это нельзя отменить. Реклама сразу исчезнет из лент.",
  "لا يمكن التراجع عن هذا. سيُزال من الخلاصات فورًا.", "Tidak bisa dibatalkan. Iklan langsung dihapus dari feed.",
  "元に戻せません。フィードからすぐに削除されます。", "되돌릴 수 없어요. 피드에서 바로 사라져요.")
K("deleteDone", "Deleted.", "Silindi.", "Eliminado.", "Excluído.", "Gelöscht.", "Supprimé.", "Eliminato.", "Удалено.", "تم الحذف.", "Dihapus.", "削除しました。", "삭제했어요.")
K("deleteFailed", "Couldn't delete: {error}", "Silinemedi: {error}", "No se pudo eliminar: {error}", "Não foi possível excluir: {error}",
  "Löschen fehlgeschlagen: {error}", "Suppression impossible : {error}", "Impossibile eliminare: {error}", "Не удалось удалить: {error}",
  "تعذّر الحذف: {error}", "Gagal menghapus: {error}", "削除できませんでした: {error}", "삭제하지 못했어요: {error}")
K("reportThanks", "Thanks — we'll take a look.", "Teşekkürler, inceleyeceğiz.", "Gracias, lo revisaremos.", "Obrigado, vamos analisar.",
  "Danke – wir sehen es uns an.", "Merci, nous allons vérifier.", "Grazie, daremo un'occhiata.", "Спасибо, мы проверим.",
  "شكرًا، سنراجع ذلك.", "Terima kasih, akan kami periksa.", "ありがとうございます。確認します。", "고마워요. 확인해 볼게요.")
K("reportFailed", "Couldn't send report: {error}", "Şikayet gönderilemedi: {error}", "No se pudo enviar la denuncia: {error}",
  "Não foi possível enviar a denúncia: {error}", "Meldung fehlgeschlagen: {error}", "Signalement impossible : {error}",
  "Impossibile inviare la segnalazione: {error}", "Не удалось отправить жалобу: {error}", "تعذّر إرسال البلاغ: {error}",
  "Gagal mengirim laporan: {error}", "報告を送信できませんでした: {error}", "신고를 보내지 못했어요: {error}")
K("reportReasonChildSafety", "Child safety", "Çocuk güvenliği", "Seguridad infantil", "Segurança infantil", "Kinderschutz",
  "Sécurité des enfants", "Sicurezza dei minori", "Безопасность детей", "سلامة الأطفال", "Keselamatan anak", "子どもの安全", "아동 안전")
K("reportReasonNudity", "Nudity or sexual content", "Çıplaklık veya cinsel içerik", "Desnudos o contenido sexual", "Nudez ou conteúdo sexual",
  "Nacktheit oder sexuelle Inhalte", "Nudité ou contenu sexuel", "Nudità o contenuti sessuali", "Нагота или сексуальный контент",
  "عُري أو محتوى جنسي", "Ketelanjangan atau konten seksual", "ヌードや性的なコンテンツ", "나체 또는 성적인 콘텐츠")
K("reportReasonViolence", "Violence", "Şiddet", "Violencia", "Violência", "Gewalt", "Violence", "Violenza", "Насилие", "عنف", "Kekerasan", "暴力", "폭력")
K("reportReasonHate", "Hate or harassment", "Nefret veya taciz", "Odio o acoso", "Ódio ou assédio", "Hass oder Belästigung",
  "Haine ou harcèlement", "Odio o molestie", "Ненависть или домогательства", "كراهية أو مضايقة", "Kebencian atau pelecehan", "ヘイトや嫌がらせ", "혐오 또는 괴롭힘")
K("reportReasonBullying", "Bullying", "Zorbalık", "Bullying", "Bullying", "Mobbing", "Harcèlement moral", "Bullismo", "Травля", "تنمّر", "Perundungan", "いじめ", "따돌림")
K("reportReasonDangerous", "Dangerous activity", "Tehlikeli eylem", "Actividad peligrosa", "Atividade perigosa", "Gefährliche Aktivität",
  "Activité dangereuse", "Attività pericolosa", "Опасные действия", "نشاط خطير", "Aktivitas berbahaya", "危険な行為", "위험한 행동")
K("reportReasonSpam", "Spam or scam", "Spam veya dolandırıcılık", "Spam o estafa", "Spam ou golpe", "Spam oder Betrug", "Spam ou arnaque",
  "Spam o truffa", "Спам или мошенничество", "رسائل مزعجة أو احتيال", "Spam atau penipuan", "スパムや詐欺", "스팸 또는 사기")
K("reportReasonCopyright", "Copyright", "Telif hakkı", "Derechos de autor", "Direitos autorais", "Urheberrecht", "Droit d'auteur", "Copyright",
  "Авторские права", "حقوق الطبع والنشر", "Hak cipta", "著作権", "저작권")
K("reportReasonImpersonation", "Impersonation", "Kimlik taklidi", "Suplantación de identidad", "Falsa identidade", "Identitätsdiebstahl",
  "Usurpation d'identité", "Furto d'identità", "Выдача себя за другого", "انتحال شخصية", "Peniruan identitas", "なりすまし", "사칭")
K("reportReasonOther", "Other", "Diğer", "Otro", "Outro", "Sonstiges", "Autre", "Altro", "Другое", "أخرى", "Lainnya", "その他", "기타")

# ---------------------------------------------------------------- subjects / market / search
K("subjectFallbackTitle", "Subject", "Konu", "Tema", "Assunto", "Thema", "Sujet", "Soggetto", "Тема", "الموضوع", "Topik", "テーマ", "주제")
K("subjectAdCount", "{count} Ads", "{count} reklam", "{count} anuncios", "{count} anúncios", "{count} Werbungen", "{count} pubs",
  "{count} pubblicità", "{count} реклам", "{count} إعلان", "{count} iklan", "広告{count}件", "광고 {count}개")
K("subjectAdThis", "AD THIS SUBJECT", "BU KONUYA REKLAM YAP", "ANUNCIA ESTE TEMA", "ANUNCIE ESTE ASSUNTO", "BEWIRB DIESES THEMA",
  "FAIS LA PUB DE CE SUJET", "PUBBLICIZZA QUESTO", "РЕКЛАМИРУЙ ЭТО", "أعلن عن هذا الموضوع", "IKLANKAN TOPIK INI", "このテーマを広告する",
  "이 주제로 광고하기")
K("subjectTabTrending", "Trending", "Trend", "Tendencias", "Em alta", "Im Trend", "Tendances", "Di tendenza", "В тренде", "الرائج", "Trending", "トレンド", "인기 급상승")
K("subjectTabTop", "Top", "En iyi", "Top", "Top", "Top", "Top", "Top", "Лучшее", "الأفضل", "Teratas", "トップ", "인기")
K("subjectTabNew", "New", "Yeni", "Nuevo", "Novo", "Neu", "Nouveau", "Nuovo", "Новое", "الأحدث", "Terbaru", "新着", "최신")
K("emptySubjectFeed", "No one's sold this yet.", "Bunu henüz kimse satmadı.", "Nadie ha vendido esto todavía.", "Ninguém vendeu isto ainda.",
  "Das hat noch niemand verkauft.", "Personne ne l'a encore vendu.", "Nessuno l'ha ancora venduto.", "Это ещё никто не продал.",
  "لم يبِع أحد هذا بعد.", "Belum ada yang menjual ini.", "まだ誰も売っていません。", "아직 아무도 팔지 않았어요.")
K("emptySubjectFeedCta", "Be the first to advertise it.", "Reklamını ilk yapan sen ol.", "Sé el primero en anunciarlo.", "Seja o primeiro a anunciar.",
  "Mach als Erste·r Werbung dafür.", "Sois le premier à en faire la pub.", "Sii il primo a pubblicizzarlo.", "Прорекламируйте первым.",
  "كن أول من يعلن عنه.", "Jadilah yang pertama mengiklankannya.", "最初の広告を作ろう。", "첫 광고를 만들어 보세요.")
K("marketFreshAds", "Fresh Ads", "Yeni reklamlar", "Anuncios nuevos", "Anúncios novos", "Neue Werbung", "Pubs récentes", "Pubblicità nuove",
  "Свежая реклама", "إعلانات جديدة", "Iklan terbaru", "新しい広告", "새 광고")
K("marketTrendingSubjects", "Trending Subjects", "Trend konular", "Temas en tendencia", "Assuntos em alta", "Angesagte Themen",
  "Sujets tendance", "Soggetti di tendenza", "Популярные темы", "المواضيع الرائجة", "Topik trending", "人気のテーマ", "인기 주제")
K("searchHint", "Search subjects or people", "Konu veya kişi ara", "Buscar temas o personas", "Buscar assuntos ou pessoas",
  "Themen oder Personen suchen", "Chercher des sujets ou des personnes", "Cerca soggetti o persone", "Искать темы или людей",
  "ابحث عن مواضيع أو أشخاص", "Cari topik atau orang", "テーマや人を検索", "주제나 사람 검색")
K("searchSubjects", "SUBJECTS", "KONULAR", "TEMAS", "ASSUNTOS", "THEMEN", "SUJETS", "SOGGETTI", "ТЕМЫ", "المواضيع", "TOPIK", "テーマ", "주제")
K("searchPeople", "PEOPLE", "KİŞİLER", "PERSONAS", "PESSOAS", "PERSONEN", "PERSONNES", "PERSONE", "ЛЮДИ", "الأشخاص", "ORANG", "人", "사람")
K("dailyAdTitle", "TODAY'S AD", "GÜNÜN REKLAMI", "EL ANUNCIO DE HOY", "O ANÚNCIO DE HOJE", "WERBUNG DES TAGES", "LA PUB DU JOUR",
  "LA PUBBLICITÀ DI OGGI", "РЕКЛАМА ДНЯ", "إعلان اليوم", "IKLAN HARI INI", "今日の広告", "오늘의 광고")
K("dailyAdJoin", "Join", "Katıl", "Unirme", "Participar", "Mitmachen", "Participer", "Partecipa", "Участвовать", "انضم", "Ikut", "参加", "참여")
K("dailyAdParticipants", "{count} participating", "{count} katılımcı", "{count} participantes", "{count} participantes", "{count} machen mit",
  "{count} participants", "{count} partecipanti", "Участников: {count}", "{count} مشارك", "{count} peserta", "{count}人が参加中", "{count}명 참여 중")

# ---------------------------------------------------------------- profile
K("profileNotFound", "This account doesn't exist.", "Bu hesap mevcut değil.", "Esta cuenta no existe.", "Esta conta não existe.",
  "Dieses Konto gibt es nicht.", "Ce compte n'existe pas.", "Questo account non esiste.", "Такого аккаунта нет.", "هذا الحساب غير موجود.",
  "Akun ini tidak ada.", "このアカウントは存在しません。", "존재하지 않는 계정이에요.")
K("profileNotSignedIn", "Not signed in.", "Giriş yapılmadı.", "No has iniciado sesión.", "Você não entrou.", "Nicht angemeldet.",
  "Non connecté.", "Accesso non effettuato.", "Вход не выполнен.", "لم تسجّل الدخول.", "Belum masuk.", "ログインしていません。", "로그인하지 않았어요.")
K("emptyProfileAds", "Nothing for sale yet.", "Henüz satışta bir şey yok.", "Aún no hay nada a la venta.", "Nada à venda ainda.",
  "Noch nichts im Angebot.", "Rien à vendre pour l'instant.", "Ancora niente in vendita.", "Пока ничего не продаётся.",
  "لا شيء للبيع بعد.", "Belum ada yang dijual.", "まだ何も売り出していません。", "아직 판매 중인 게 없어요.")
K("statAds", "Ads", "Reklam", "Anuncios", "Anúncios", "Werbungen", "Pubs", "Pubblicità", "Реклама", "إعلانات", "Iklan", "広告", "광고")
K("statViews", "Views", "İzlenme", "Vistas", "Visualizações", "Aufrufe", "Vues", "Visualizzazioni", "Просмотры", "مشاهدات", "Tayangan", "再生数", "조회수")
K("profileEditProfile", "Edit profile", "Profili düzenle", "Editar perfil", "Editar perfil", "Profil bearbeiten", "Modifier le profil",
  "Modifica profilo", "Изменить профиль", "تعديل الملف الشخصي", "Edit profil", "プロフィールを編集", "프로필 편집")
K("profileMenuTooltip", "Settings", "Ayarlar", "Ajustes", "Configurações", "Einstellungen", "Paramètres", "Impostazioni", "Настройки",
  "الإعدادات", "Pengaturan", "設定", "설정")
K("displayNameLabel", "Display name", "Görünen ad", "Nombre visible", "Nome de exibição", "Anzeigename", "Nom affiché", "Nome visualizzato",
  "Отображаемое имя", "الاسم المعروض", "Nama tampilan", "表示名", "표시 이름")
K("bioLabel", "Bio", "Biyografi", "Biografía", "Bio", "Bio", "Bio", "Bio", "О себе", "نبذة", "Bio", "自己紹介", "소개")
K("avatarUploadFailed", "Couldn't upload photo: {error}", "Fotoğraf yüklenemedi: {error}", "No se pudo subir la foto: {error}",
  "Não foi possível enviar a foto: {error}", "Foto konnte nicht hochgeladen werden: {error}", "Envoi de la photo impossible : {error}",
  "Impossibile caricare la foto: {error}", "Не удалось загрузить фото: {error}", "تعذّر رفع الصورة: {error}", "Gagal mengunggah foto: {error}",
  "写真をアップロードできませんでした: {error}", "사진을 올리지 못했어요: {error}")
K("saveFailed", "Couldn't save: {error}", "Kaydedilemedi: {error}", "No se pudo guardar: {error}", "Não foi possível salvar: {error}",
  "Speichern fehlgeschlagen: {error}", "Enregistrement impossible : {error}", "Impossibile salvare: {error}", "Не удалось сохранить: {error}",
  "تعذّر الحفظ: {error}", "Gagal menyimpan: {error}", "保存できませんでした: {error}", "저장하지 못했어요: {error}")

# ---------------------------------------------------------------- activity
K("activityEmptyTitle", "Nothing yet", "Henüz bir şey yok", "Nada todavía", "Nada ainda", "Noch nichts", "Rien pour l'instant", "Ancora niente",
  "Пока ничего", "لا شيء بعد", "Belum ada apa-apa", "まだ何もありません", "아직 아무것도 없어요")
K("activityEmptyBody", "Follows, REVIEWS and AD THIS on your Ads will show up here.",
  "Takipler, REVIEWS ve reklamlarına gelen AD THIS'ler burada görünecek.",
  "Aquí verás seguidores, REVIEWS y AD THIS de tus anuncios.", "Seguidores, REVIEWS e AD THIS nos seus anúncios aparecem aqui.",
  "Neue Follower, REVIEWS und AD THIS zu deiner Werbung erscheinen hier.", "Abonnés, REVIEWS et AD THIS sur tes pubs apparaîtront ici.",
  "Qui vedrai follower, REVIEWS e AD THIS sulle tue pubblicità.", "Здесь появятся подписки, REVIEWS и AD THIS к вашей рекламе.",
  "ستظهر هنا المتابعات وREVIEWS وAD THIS على إعلاناتك.", "Pengikut, REVIEWS, dan AD THIS di iklanmu akan muncul di sini.",
  "フォロー、REVIEWS、あなたの広告へのAD THISがここに表示されます。", "팔로우, REVIEWS, 내 광고의 AD THIS가 여기에 표시돼요.")
K("activitySomeone", "Someone", "Birisi", "Alguien", "Alguém", "Jemand", "Quelqu'un", "Qualcuno", "Кто-то", "شخص ما", "Seseorang", "誰か", "누군가")
K("activityNewFollower", "{actor} started following you.", "{actor} seni takip etmeye başladı.", "{actor} empezó a seguirte.",
  "{actor} começou a seguir você.", "{actor} folgt dir jetzt.", "{actor} s'est abonné à toi.", "{actor} ha iniziato a seguirti.",
  "{actor} подписался на вас.", "بدأ {actor} بمتابعتك.", "{actor} mulai mengikutimu.", "{actor}さんがあなたをフォローしました。",
  "{actor}님이 회원님을 팔로우하기 시작했어요.")
K("activityNewReview", "{actor} reviewed your Ad.", "{actor} reklamına yorum yaptı.", "{actor} comentó tu anuncio.",
  "{actor} avaliou seu anúncio.", "{actor} hat deine Werbung bewertet.", "{actor} a laissé un avis sur ta pub.",
  "{actor} ha recensito la tua pubblicità.", "{actor} оставил отзыв о вашей рекламе.", "علّق {actor} على إعلانك.",
  "{actor} mengulas iklanmu.", "{actor}さんがあなたの広告にレビューしました。", "{actor}님이 내 광고에 리뷰를 남겼어요.")
K("activityAdThis", "{actor} pressed AD THIS on your Ad.", "{actor} reklamında AD THIS'e bastı.", "{actor} pulsó AD THIS en tu anuncio.",
  "{actor} tocou em AD THIS no seu anúncio.", "{actor} hat bei deiner Werbung AD THIS gedrückt.", "{actor} a appuyé sur AD THIS sur ta pub.",
  "{actor} ha premuto AD THIS sulla tua pubblicità.", "{actor} нажал AD THIS на вашей рекламе.", "ضغط {actor} على AD THIS في إعلانك.",
  "{actor} menekan AD THIS di iklanmu.", "{actor}さんがあなたの広告でAD THISを押しました。", "{actor}님이 내 광고에서 AD THIS를 눌렀어요.")
K("timeJustNow", "just now", "az önce", "ahora", "agora", "gerade eben", "à l'instant", "adesso", "только что", "الآن", "baru saja", "たった今", "방금")
K("timeMinutesAgo", "{n}m ago", "{n} dk önce", "hace {n} min", "há {n} min", "vor {n} Min.", "il y a {n} min", "{n} min fa", "{n} мин назад",
  "منذ {n} د", "{n} mnt lalu", "{n}分前", "{n}분 전")
K("timeHoursAgo", "{n}h ago", "{n} sa önce", "hace {n} h", "há {n} h", "vor {n} Std.", "il y a {n} h", "{n} h fa", "{n} ч назад",
  "منذ {n} س", "{n} jam lalu", "{n}時間前", "{n}시간 전")
K("timeDaysAgo", "{n}d ago", "{n} gün önce", "hace {n} d", "há {n} d", "vor {n} T.", "il y a {n} j", "{n} g fa", "{n} д назад",
  "منذ {n} ي", "{n} hari lalu", "{n}日前", "{n}일 전")

# ---------------------------------------------------------------- create flow
K("createChooseSubject", "What are you selling today?", "Bugün ne satıyorsun?", "¿Qué vendes hoy?", "O que você vende hoje?",
  "Was verkaufst du heute?", "Tu vends quoi aujourd'hui ?", "Cosa vendi oggi?", "Что продаёте сегодня?", "ماذا تبيع اليوم؟",
  "Jual apa hari ini?", "今日は何を売る？", "오늘은 뭘 팔까요?")
K("createSubjectHint", "Rock, coffee, Monday, yourself…", "Taş, kahve, pazartesi, kendin…", "Piedra, café, lunes, tú…",
  "Pedra, café, segunda, você…", "Stein, Kaffee, Montag, du selbst…", "Caillou, café, lundi, toi…", "Sasso, caffè, lunedì, te stesso…",
  "Камень, кофе, понедельник, ты сам…", "حجر، قهوة، الاثنين، نفسك…", "Batu, kopi, Senin, dirimu…", "石、コーヒー、月曜日、自分…",
  "돌멩이, 커피, 월요일, 나 자신…")
K("captureTitle", "Record or import", "Kaydet ya da içe aktar", "Graba o importa", "Grave ou importe", "Aufnehmen oder importieren",
  "Filmer ou importer", "Registra o importa", "Запись или импорт", "سجّل أو استورد", "Rekam atau impor", "撮影または読み込み", "녹화 또는 가져오기")
K("createRecord", "Record", "Kaydet", "Grabar", "Gravar", "Aufnehmen", "Filmer", "Registra", "Записать", "تسجيل", "Rekam", "撮影", "녹화")
K("createImport", "Import from gallery", "Galeriden seç", "Importar de la galería", "Importar da galeria", "Aus Galerie importieren",
  "Importer depuis la galerie", "Importa dalla galleria", "Импорт из галереи", "استيراد من المعرض", "Impor dari galeri",
  "ギャラリーから読み込む", "갤러리에서 가져오기")
K("importFailed", "Couldn't import that video: {error}", "Bu video içe aktarılamadı: {error}", "No se pudo importar el video: {error}",
  "Não foi possível importar o vídeo: {error}", "Video konnte nicht importiert werden: {error}", "Import de la vidéo impossible : {error}",
  "Impossibile importare il video: {error}", "Не удалось импортировать видео: {error}", "تعذّر استيراد الفيديو: {error}",
  "Gagal mengimpor video: {error}", "動画を読み込めませんでした: {error}", "동영상을 가져오지 못했어요: {error}")
K("cameraPermission", "Camera and microphone access is needed to record.", "Kayıt için kamera ve mikrofon izni gerekiyor.",
  "Se necesita acceso a la cámara y al micrófono para grabar.", "É preciso acesso à câmera e ao microfone para gravar.",
  "Zum Aufnehmen brauchen wir Zugriff auf Kamera und Mikrofon.", "L'accès à la caméra et au micro est nécessaire pour filmer.",
  "Per registrare serve l'accesso a fotocamera e microfono.", "Для записи нужен доступ к камере и микрофону.",
  "يلزم الوصول إلى الكاميرا والميكروفون للتسجيل.", "Perlu akses kamera dan mikrofon untuk merekam.",
  "撮影にはカメラとマイクへのアクセスが必要です。", "녹화하려면 카메라와 마이크 권한이 필요해요.")
K("cameraStartFailed", "Couldn't start the camera: {error}", "Kamera başlatılamadı: {error}", "No se pudo iniciar la cámara: {error}",
  "Não foi possível abrir a câmera: {error}", "Kamera konnte nicht gestartet werden: {error}", "Impossible de démarrer la caméra : {error}",
  "Impossibile avviare la fotocamera: {error}", "Не удалось запустить камеру: {error}", "تعذّر تشغيل الكاميرا: {error}",
  "Gagal membuka kamera: {error}", "カメラを起動できませんでした: {error}", "카메라를 시작하지 못했어요: {error}")
K("cameraSwitchFailed", "Couldn't switch camera: {error}", "Kamera değiştirilemedi: {error}", "No se pudo cambiar de cámara: {error}",
  "Não foi possível trocar a câmera: {error}", "Kamerawechsel fehlgeschlagen: {error}", "Changement de caméra impossible : {error}",
  "Impossibile cambiare fotocamera: {error}", "Не удалось переключить камеру: {error}", "تعذّر تبديل الكاميرا: {error}",
  "Gagal mengganti kamera: {error}", "カメラを切り替えられませんでした: {error}", "카메라를 전환하지 못했어요: {error}")
K("cameraTooShort", "Too short — hold on a little longer.", "Çok kısa — biraz daha uzun kaydet.", "Muy corto: graba un poco más.",
  "Curto demais: grave um pouco mais.", "Zu kurz – nimm etwas länger auf.", "Trop court : filme un peu plus longtemps.",
  "Troppo corto: registra un po' di più.", "Слишком коротко — снимайте чуть дольше.", "قصير جدًا — سجّل مدة أطول قليلًا.",
  "Terlalu pendek — rekam sedikit lebih lama.", "短すぎます。もう少し長く撮ってください。", "너무 짧아요. 조금 더 길게 찍어 주세요.")
K("captureCancelExtraClip", "Cancel", "Vazgeç", "Cancelar", "Cancelar", "Abbrechen", "Annuler", "Annulla", "Отмена", "إلغاء", "Batal", "キャンセル", "취소")
K("editorCrashedLast", "The editor closed unexpectedly last time. This is what happened just before:",
  "Editör geçen sefer beklenmedik şekilde kapandı. Hemen öncesinde olanlar:",
  "El editor se cerró inesperadamente la última vez. Esto pasó justo antes:",
  "O editor fechou inesperadamente da última vez. Isto aconteceu logo antes:",
  "Der Editor wurde letztes Mal unerwartet geschlossen. Das geschah kurz davor:",
  "L'éditeur s'est fermé de façon inattendue la dernière fois. Voici ce qui s'est passé juste avant :",
  "L'editor si è chiuso inaspettatamente l'ultima volta. Ecco cosa è successo prima:",
  "В прошлый раз редактор неожиданно закрылся. Вот что было перед этим:",
  "أُغلق المحرر بشكل غير متوقع في المرة الماضية. هذا ما حدث قبل ذلك مباشرة:",
  "Editor tertutup tiba-tiba terakhir kali. Ini yang terjadi sebelumnya:",
  "前回エディターが予期せず終了しました。直前の記録:", "지난번 편집기가 예기치 않게 종료됐어요. 직전 기록:")
K("editorFailed", "The editor couldn't open", "Editör açılamadı", "No se pudo abrir el editor", "Não foi possível abrir o editor",
  "Der Editor konnte nicht geöffnet werden", "Impossible d'ouvrir l'éditeur", "Impossibile aprire l'editor", "Не удалось открыть редактор",
  "تعذّر فتح المحرر", "Editor tidak bisa dibuka", "エディターを開けませんでした", "편집기를 열지 못했어요")
K("previewPublishTitle", "Preview & publish", "Önizle ve yayınla", "Vista previa y publicar", "Prévia e publicação", "Vorschau & veröffentlichen",
  "Aperçu et publication", "Anteprima e pubblica", "Просмотр и публикация", "المعاينة والنشر", "Pratinjau & terbitkan", "プレビューと公開", "미리보기 및 게시")
K("retake", "Retake", "Yeniden çek", "Repetir", "Refazer", "Neu aufnehmen", "Refaire", "Rifai", "Переснять", "إعادة التصوير", "Ulangi", "撮り直す", "다시 찍기")
K("createCaptionHint", "Add a caption…", "Açıklama ekle…", "Añade una descripción…", "Adicione uma legenda…", "Beschreibung hinzufügen…",
  "Ajoute une légende…", "Aggiungi una didascalia…", "Добавьте подпись…", "أضف وصفًا…", "Tambahkan keterangan…", "キャプションを追加…", "설명 추가…")
K("createPublish", "Publish", "Yayınla", "Publicar", "Publicar", "Veröffentlichen", "Publier", "Pubblica", "Опубликовать", "نشر", "Terbitkan", "公開", "게시")
K("createUploading", "Uploading…", "Yükleniyor…", "Subiendo…", "Enviando…", "Wird hochgeladen…", "Envoi…", "Caricamento…", "Загрузка…",
  "جارٍ الرفع…", "Mengunggah…", "アップロード中…", "업로드 중…")
K("createUploadingProgress", "Uploading… {percent}%", "Yükleniyor… %{percent}", "Subiendo… {percent} %", "Enviando… {percent}%",
  "Wird hochgeladen… {percent} %", "Envoi… {percent} %", "Caricamento… {percent}%", "Загрузка… {percent}%", "جارٍ الرفع… {percent}٪",
  "Mengunggah… {percent}%", "アップロード中… {percent}%", "업로드 중… {percent}%")
K("createProcessing", "Processing…", "İşleniyor…", "Procesando…", "Processando…", "Wird verarbeitet…", "Traitement…", "Elaborazione…",
  "Обработка…", "جارٍ المعالجة…", "Memproses…", "処理中…", "처리 중…")
K("publishStillProcessing", "Still processing — it'll show up on your profile soon.",
  "Hâlâ işleniyor — kısa süre içinde profilinde görünecek.", "Aún se está procesando; pronto aparecerá en tu perfil.",
  "Ainda processando; logo aparecerá no seu perfil.", "Wird noch verarbeitet – bald erscheint es in deinem Profil.",
  "Traitement en cours : elle apparaîtra bientôt sur ton profil.", "Ancora in elaborazione: presto sarà sul tuo profilo.",
  "Ещё обрабатывается — скоро появится в профиле.", "لا تزال قيد المعالجة — ستظهر في ملفك قريبًا.",
  "Masih diproses — sebentar lagi muncul di profilmu.", "処理中です。まもなくプロフィールに表示されます。", "아직 처리 중이에요. 곧 프로필에 나타나요.")
K("publishDone", "Published!", "Yayınlandı!", "¡Publicado!", "Publicado!", "Veröffentlicht!", "Publié !", "Pubblicato!", "Опубликовано!",
  "تم النشر!", "Terbit!", "公開しました！", "게시했어요!")
K("draftFailed", "This one didn't make the campaign.", "Bu reklam kampanyaya giremedi.", "Este no llegó a la campaña.",
  "Este não entrou na campanha.", "Das hat es nicht in die Kampagne geschafft.", "Celle-ci n'a pas passé le casting.",
  "Questa non è entrata nella campagna.", "Этот ролик не прошёл в кампанию.", "هذا الإعلان لم يدخل الحملة.",
  "Yang ini gagal masuk kampanye.", "今回はキャンペーンに間に合いませんでした。", "이번 광고는 캠페인에 들어가지 못했어요.")

# ---------------------------------------------------------------- settings
K("settingsTitle", "Settings", "Ayarlar", "Ajustes", "Configurações", "Einstellungen", "Paramètres", "Impostazioni", "Настройки",
  "الإعدادات", "Pengaturan", "設定", "설정")
K("settingsSectionAccount", "Your account", "Hesabın", "Tu cuenta", "Sua conta", "Dein Konto", "Ton compte", "Il tuo account", "Ваш аккаунт",
  "حسابك", "Akunmu", "アカウント", "내 계정")
K("settingsEditProfile", "Edit profile", "Profili düzenle", "Editar perfil", "Editar perfil", "Profil bearbeiten", "Modifier le profil",
  "Modifica profilo", "Изменить профиль", "تعديل الملف الشخصي", "Edit profil", "プロフィールを編集", "프로필 편집")
K("settingsAccount", "Account", "Hesap", "Cuenta", "Conta", "Konto", "Compte", "Account", "Аккаунт", "الحساب", "Akun", "アカウント", "계정")
K("settingsAccountSubtitle", "Email, password", "E-posta, şifre", "Email, contraseña", "E-mail, senha", "E-Mail, Passwort",
  "E-mail, mot de passe", "Email, password", "Email, пароль", "البريد الإلكتروني، كلمة المرور", "Email, kata sandi", "メール、パスワード", "이메일, 비밀번호")
K("settingsSectionPrivacy", "Who can see your content", "İçeriğini kimler görebilir", "Quién puede ver tu contenido",
  "Quem pode ver seu conteúdo", "Wer deine Inhalte sehen kann", "Qui peut voir ton contenu", "Chi può vedere i tuoi contenuti",
  "Кто видит ваш контент", "من يمكنه رؤية المحتوى الخاص بك", "Siapa yang bisa melihat kontenmu", "コンテンツを見られる人", "내 콘텐츠를 볼 수 있는 사람")
K("settingsBlocked", "Blocked", "Engellenenler", "Bloqueados", "Bloqueados", "Blockiert", "Bloqués", "Bloccati", "Заблокированные",
  "المحظورون", "Diblokir", "ブロック中", "차단됨")
K("settingsSectionApp", "Your app and media", "Uygulaman ve medya", "Tu app y contenido", "Seu app e mídia", "App und Medien",
  "Ton app et tes médias", "App e contenuti multimediali", "Приложение и медиа", "التطبيق والوسائط", "Aplikasi dan media", "アプリとメディア",
  "앱 및 미디어")
K("settingsLanguage", "Language", "Dil", "Idioma", "Idioma", "Sprache", "Langue", "Lingua", "Язык", "اللغة", "Bahasa", "言語", "언어")
K("settingsLanguageSystem", "Device language", "Cihaz dili", "Idioma del dispositivo", "Idioma do aparelho", "Gerätesprache",
  "Langue de l'appareil", "Lingua del dispositivo", "Язык устройства", "لغة الجهاز", "Bahasa perangkat", "端末の言語", "기기 언어")
K("settingsAppearance", "Appearance", "Görünüm", "Apariencia", "Aparência", "Darstellung", "Apparence", "Aspetto", "Оформление", "المظهر",
  "Tampilan", "外観", "화면 모드")
K("settingsThemeSystem", "Use device setting", "Cihaz ayarını kullan", "Usar ajuste del dispositivo", "Usar ajuste do aparelho",
  "Geräteeinstellung verwenden", "Utiliser le réglage de l'appareil", "Usa impostazione del dispositivo", "Как на устройстве",
  "استخدام إعداد الجهاز", "Ikuti pengaturan perangkat", "端末の設定に合わせる", "기기 설정 사용")
K("settingsThemeLight", "Light", "Açık", "Claro", "Claro", "Hell", "Clair", "Chiaro", "Светлое", "فاتح", "Terang", "ライト", "라이트")
K("settingsThemeDark", "Dark", "Koyu", "Oscuro", "Escuro", "Dunkel", "Sombre", "Scuro", "Тёмное", "داكن", "Gelap", "ダーク", "다크")
K("settingsSectionMore", "More info and support", "Daha fazla bilgi ve destek", "Más información y ayuda", "Mais informações e suporte",
  "Weitere Infos und Hilfe", "Plus d'infos et assistance", "Altre info e assistenza", "Информация и поддержка", "مزيد من المعلومات والدعم",
  "Info lainnya dan bantuan", "詳細とサポート", "추가 정보 및 지원")
K("settingsAbout", "About", "Hakkında", "Acerca de", "Sobre", "Über", "À propos", "Info", "О приложении", "حول", "Tentang", "このアプリについて", "정보")
K("settingsSectionLogin", "Login", "Giriş", "Inicio de sesión", "Login", "Anmeldung", "Connexion", "Accesso", "Вход", "تسجيل الدخول", "Masuk", "ログイン", "로그인")
K("settingsLogOut", "Log out {username}", "{username} hesabından çıkış yap", "Cerrar sesión de {username}", "Sair de {username}",
  "{username} abmelden", "Déconnecter {username}", "Esci da {username}", "Выйти из {username}", "تسجيل الخروج من {username}",
  "Keluar dari {username}", "{username}からログアウト", "{username} 로그아웃")
K("settingsLogOutConfirmTitle", "Log out of your account?", "Hesabından çıkış yapılsın mı?", "¿Cerrar sesión?", "Sair da sua conta?",
  "Von deinem Konto abmelden?", "Te déconnecter ?", "Uscire dall'account?", "Выйти из аккаунта?", "تسجيل الخروج من حسابك؟",
  "Keluar dari akunmu?", "ログアウトしますか？", "로그아웃할까요?")
K("settingsLogOutConfirm", "Log out", "Çıkış yap", "Cerrar sesión", "Sair", "Abmelden", "Se déconnecter", "Esci", "Выйти", "تسجيل الخروج",
  "Keluar", "ログアウト", "로그아웃")
K("accountEmail", "Email", "E-posta", "Email", "E-mail", "E-Mail", "E-mail", "Email", "Email", "البريد الإلكتروني", "Email", "メールアドレス", "이메일")
K("accountEmailNote", "Only you can see this.", "Bunu sadece sen görebilirsin.", "Solo tú puedes verlo.", "Só você pode ver isso.",
  "Nur du kannst das sehen.", "Toi seul peux voir ceci.", "Solo tu puoi vederlo.", "Это видите только вы.", "أنت فقط من يمكنه رؤية هذا.",
  "Hanya kamu yang bisa melihat ini.", "これはあなただけに表示されます。", "나만 볼 수 있어요.")
K("accountChangePassword", "Change password", "Şifreyi değiştir", "Cambiar contraseña", "Alterar senha", "Passwort ändern",
  "Changer le mot de passe", "Cambia password", "Сменить пароль", "تغيير كلمة المرور", "Ubah kata sandi", "パスワードを変更", "비밀번호 변경")
K("accountNewPassword", "New password", "Yeni şifre", "Nueva contraseña", "Nova senha", "Neues Passwort", "Nouveau mot de passe",
  "Nuova password", "Новый пароль", "كلمة المرور الجديدة", "Kata sandi baru", "新しいパスワード", "새 비밀번호")
K("accountConfirmPassword", "Confirm new password", "Yeni şifreyi tekrarla", "Confirma la nueva contraseña", "Confirme a nova senha",
  "Neues Passwort bestätigen", "Confirme le nouveau mot de passe", "Conferma la nuova password", "Повторите новый пароль",
  "تأكيد كلمة المرور الجديدة", "Konfirmasi kata sandi baru", "新しいパスワード（確認）", "새 비밀번호 확인")
K("accountPasswordTooShort", "At least 8 characters", "En az 8 karakter", "Al menos 8 caracteres", "Pelo menos 8 caracteres",
  "Mindestens 8 Zeichen", "Au moins 8 caractères", "Almeno 8 caratteri", "Не менее 8 символов", "8 أحرف على الأقل", "Minimal 8 karakter",
  "8文字以上", "8자 이상")
K("accountPasswordMismatch", "Passwords don't match", "Şifreler eşleşmiyor", "Las contraseñas no coinciden", "As senhas não coincidem",
  "Passwörter stimmen nicht überein", "Les mots de passe ne correspondent pas", "Le password non coincidono", "Пароли не совпадают",
  "كلمتا المرور غير متطابقتين", "Kata sandi tidak cocok", "パスワードが一致しません", "비밀번호가 일치하지 않아요")
K("accountPasswordChanged", "Password changed.", "Şifre değiştirildi.", "Contraseña cambiada.", "Senha alterada.", "Passwort geändert.",
  "Mot de passe modifié.", "Password cambiata.", "Пароль изменён.", "تم تغيير كلمة المرور.", "Kata sandi diubah.", "パスワードを変更しました。",
  "비밀번호를 변경했어요.")
K("blockedEmpty", "You haven't blocked anyone", "Kimseyi engellemedin", "No has bloqueado a nadie", "Você não bloqueou ninguém",
  "Du hast niemanden blockiert", "Tu n'as bloqué personne", "Non hai bloccato nessuno", "Вы никого не блокировали", "لم تحظر أحدًا",
  "Kamu belum memblokir siapa pun", "ブロックしている人はいません", "차단한 사람이 없어요")
K("blockedEmptyNote", "When you block someone, they show up here. They can't see your Ads or follow you.",
  "Birini engellediğinde burada görünür. Reklamlarını göremez ve seni takip edemez.",
  "Las personas que bloquees aparecerán aquí. No pueden ver tus anuncios ni seguirte.",
  "Quem você bloquear aparece aqui. Essas pessoas não podem ver seus anúncios nem seguir você.",
  "Blockierte Personen erscheinen hier. Sie können deine Werbung nicht sehen und dir nicht folgen.",
  "Les personnes bloquées apparaissent ici. Elles ne peuvent ni voir tes pubs ni te suivre.",
  "Le persone bloccate compaiono qui. Non possono vedere le tue pubblicità né seguirti.",
  "Заблокированные появятся здесь. Они не видят вашу рекламу и не могут подписаться.",
  "يظهر هنا من تحظرهم. لا يمكنهم رؤية إعلاناتك أو متابعتك.",
  "Orang yang kamu blokir muncul di sini. Mereka tidak bisa melihat iklanmu atau mengikutimu.",
  "ブロックした人はここに表示されます。あなたの広告を見たりフォローしたりできません。",
  "차단한 사람은 여기에 표시돼요. 내 광고를 보거나 나를 팔로우할 수 없어요.")
K("blockedUnblock", "Unblock", "Engeli kaldır", "Desbloquear", "Desbloquear", "Blockierung aufheben", "Débloquer", "Sblocca", "Разблокировать",
  "إلغاء الحظر", "Buka blokir", "ブロック解除", "차단 해제")
K("blockedUnblockConfirmTitle", "Unblock @{username}?", "@{username} kişisinin engeli kaldırılsın mı?", "¿Desbloquear a @{username}?",
  "Desbloquear @{username}?", "@{username} entsperren?", "Débloquer @{username} ?", "Sbloccare @{username}?", "Разблокировать @{username}?",
  "إلغاء حظر @{username}؟", "Buka blokir @{username}?", "@{username}のブロックを解除しますか？", "@{username}님을 차단 해제할까요?")
K("blockedUnblockConfirmNote", "They'll be able to see your Ads and follow you again. They won't be notified.",
  "Reklamlarını yeniden görebilir ve seni takip edebilir. Kendisine bildirim gitmez.",
  "Podrá volver a ver tus anuncios y seguirte. No recibirá ningún aviso.",
  "Essa pessoa poderá ver seus anúncios e seguir você de novo. Ela não será notificada.",
  "Die Person kann deine Werbung wieder sehen und dir folgen. Sie wird nicht benachrichtigt.",
  "Cette personne pourra de nouveau voir tes pubs et te suivre. Elle ne sera pas prévenue.",
  "Potrà di nuovo vedere le tue pubblicità e seguirti. Non riceverà notifiche.",
  "Пользователь снова сможет видеть вашу рекламу и подписаться. Уведомления не будет.",
  "سيتمكن من رؤية إعلاناتك ومتابعتك مجددًا. لن يتلقى إشعارًا.",
  "Mereka bisa melihat iklanmu dan mengikutimu lagi. Mereka tidak akan diberi tahu.",
  "相手は再びあなたの広告を見たりフォローしたりできます。通知はされません。",
  "상대가 다시 내 광고를 보고 나를 팔로우할 수 있어요. 알림은 가지 않아요.")
K("blockedLoadError", "Couldn't load your blocked accounts.", "Engellenen hesaplar yüklenemedi.", "No se pudieron cargar las cuentas bloqueadas.",
  "Não foi possível carregar as contas bloqueadas.", "Blockierte Konten konnten nicht geladen werden.", "Impossible de charger les comptes bloqués.",
  "Impossibile caricare gli account bloccati.", "Не удалось загрузить заблокированных.", "تعذّر تحميل الحسابات المحظورة.",
  "Gagal memuat akun yang diblokir.", "ブロック中のアカウントを読み込めませんでした。", "차단한 계정을 불러오지 못했어요.")
K("aboutOpenSourceLibraries", "Open source libraries", "Açık kaynak kütüphaneler", "Bibliotecas de código abierto", "Bibliotecas de código aberto",
  "Open-Source-Bibliotheken", "Bibliothèques open source", "Librerie open source", "Библиотеки с открытым кодом", "مكتبات مفتوحة المصدر",
  "Pustaka sumber terbuka", "オープンソースライブラリ", "오픈소스 라이브러리")
K("aboutOpenSourceLibrariesSubtitle", "Licenses of the software AdGag uses", "AdGag'in kullandığı yazılımların lisansları",
  "Licencias del software que usa AdGag", "Licenças do software que o AdGag usa", "Lizenzen der Software, die AdGag nutzt",
  "Licences des logiciels utilisés par AdGag", "Licenze del software usato da AdGag", "Лицензии ПО, которое использует AdGag",
  "تراخيص البرمجيات التي يستخدمها AdGag", "Lisensi perangkat lunak yang dipakai AdGag", "AdGagが使用しているソフトウェアのライセンス",
  "AdGag에서 사용하는 소프트웨어 라이선스")
K("authConfirmedTitle", "Your account is confirmed!", "Hesabın onaylandı!", "¡Tu cuenta está confirmada!", "Sua conta foi confirmada!",
  "Dein Konto ist bestätigt!", "Ton compte est confirmé !", "Il tuo account è confermato!", "Аккаунт подтверждён!",
  "تم تأكيد حسابك!", "Akunmu sudah dikonfirmasi!", "アカウントが確認されました！", "계정이 확인됐어요!")
K("authConfirmedBody", "Welcome to AdGag. Pick something and sell it.", "AdGag'e hoş geldin. Bir şey seç ve sat.",
  "Bienvenido a AdGag. Elige algo y véndelo.", "Bem-vindo ao AdGag. Escolha algo e venda.",
  "Willkommen bei AdGag. Such dir etwas aus und verkauf es.", "Bienvenue sur AdGag. Choisis quelque chose et vends-le.",
  "Benvenuto su AdGag. Scegli qualcosa e vendilo.", "Добро пожаловать в AdGag. Выбери что угодно и продай это.",
  "مرحباً بك في AdGag. اختر أي شيء وبِعه.", "Selamat datang di AdGag. Pilih sesuatu dan jual.",
  "AdGagへようこそ。何かを選んで売り込もう。", "AdGag에 오신 걸 환영해요. 무엇이든 골라서 팔아 보세요.")
K("authConfirmedStart", "Let's go", "Başlayalım", "¡Vamos!", "Vamos lá", "Los geht's", "C'est parti", "Iniziamo", "Поехали",
  "هيا بنا", "Ayo mulai", "はじめる", "시작하기")
K("authResend", "Resend email", "E-postayı tekrar gönder", "Reenviar email", "Reenviar e-mail", "E-Mail erneut senden",
  "Renvoyer l'e-mail", "Invia di nuovo l'email", "Отправить письмо ещё раз", "إعادة إرسال البريد", "Kirim ulang email",
  "メールを再送信", "이메일 다시 보내기")

# --- Follow stats (profiles) ---
K("statFollowers", "Followers", "Takipçi", "Seguidores", "Seguidores", "Follower", "Abonnés", "Follower", "Подписчики", "المتابعون",
  "Pengikut", "フォロワー", "팔로워")
K("statFollowing", "Following", "Takip", "Siguiendo", "Seguindo", "Gefolgt", "Abonnements", "Seguiti", "Подписки", "يتابع",
  "Mengikuti", "フォロー中", "팔로잉")
K("followersEmpty", "No followers yet.", "Henüz takipçi yok.", "Aún no hay seguidores.", "Ainda não há seguidores.",
  "Noch keine Follower.", "Pas encore d'abonnés.", "Ancora nessun follower.", "Подписчиков пока нет.", "لا يوجد متابعون بعد.",
  "Belum ada pengikut.", "まだフォロワーはいません。", "아직 팔로워가 없어요.")
K("followingEmpty", "Not following anyone yet.", "Henüz kimse takip edilmiyor.", "Aún no sigue a nadie.", "Ainda não segue ninguém.",
  "Folgt noch niemandem.", "Ne suit encore personne.", "Non segue ancora nessuno.", "Пока ни на кого не подписан.",
  "لا يتابع أحدًا بعد.", "Belum mengikuti siapa pun.", "まだ誰もフォローしていません。", "아직 아무도 팔로우하지 않아요.")

# --- Account deletion (Settings > Account) ---
K("accountDelete", "Delete account", "Hesabı sil", "Eliminar cuenta", "Excluir conta", "Konto löschen", "Supprimer le compte",
  "Elimina account", "Удалить аккаунт", "حذف الحساب", "Hapus akun", "アカウントを削除", "계정 삭제")
K("accountDeleteSubtitle", "Permanently delete your account and your Ads", "Hesabını ve reklamlarını kalıcı olarak sil",
  "Elimina para siempre tu cuenta y tus anuncios", "Exclua permanentemente sua conta e seus anúncios",
  "Dein Konto und deine Werbungen endgültig löschen", "Supprimer définitivement ton compte et tes pubs",
  "Elimina per sempre il tuo account e le tue pubblicità", "Навсегда удалить аккаунт и вашу рекламу",
  "احذف حسابك وإعلاناتك نهائيًا", "Hapus akun dan iklanmu secara permanen", "アカウントと広告を完全に削除します",
  "계정과 광고를 영구적으로 삭제해요")
K("accountDeleteTitle", "Delete your account?", "Hesabın silinsin mi?", "¿Eliminar tu cuenta?", "Excluir sua conta?",
  "Konto löschen?", "Supprimer ton compte ?", "Eliminare il tuo account?", "Удалить аккаунт?", "حذف حسابك؟", "Hapus akunmu?",
  "アカウントを削除しますか？", "계정을 삭제할까요?")
K("accountDeleteBody",
  "This permanently deletes your account, your Ads and their videos, your reviews, SOLDs and follows. It can't be undone.",
  "Hesabın, reklamların ve videoları, yorumların, SOLD'ların ve takiplerin kalıcı olarak silinir. Bu işlem geri alınamaz.",
  "Esto elimina para siempre tu cuenta, tus anuncios y sus videos, tus reseñas, SOLD y seguimientos. No se puede deshacer.",
  "Isso exclui permanentemente sua conta, seus anúncios e vídeos, suas avaliações, SOLDs e seguidos. Não pode ser desfeito.",
  "Dein Konto, deine Werbungen samt Videos, Bewertungen, SOLDs und Follows werden endgültig gelöscht. Das kann nicht rückgängig gemacht werden.",
  "Ton compte, tes pubs et leurs vidéos, tes avis, tes SOLD et tes abonnements seront supprimés définitivement. C'est irréversible.",
  "Il tuo account, le tue pubblicità e i relativi video, le recensioni, i SOLD e i follow verranno eliminati per sempre. Non si può annullare.",
  "Аккаунт, ваша реклама с видео, отзывы, SOLD и подписки будут удалены навсегда. Это нельзя отменить.",
  "سيؤدي هذا إلى حذف حسابك وإعلاناتك ومقاطعها ومراجعاتك وSOLD والمتابعات نهائيًا. لا يمكن التراجع عن ذلك.",
  "Ini menghapus akun, iklan beserta videonya, ulasan, SOLD, dan ikutanmu secara permanen. Tidak bisa dibatalkan.",
  "アカウント、広告とその動画、レビュー、SOLD、フォローが完全に削除されます。元に戻せません。",
  "계정, 광고와 영상, 리뷰, SOLD, 팔로우가 영구적으로 삭제돼요. 되돌릴 수 없어요.")
K("accountDeleteConfirmHint", "Type {username} to confirm", "Onaylamak için {username} yaz", "Escribe {username} para confirmar",
  "Digite {username} para confirmar", "Zur Bestätigung {username} eingeben", "Tape {username} pour confirmer",
  "Scrivi {username} per confermare", "Введите {username} для подтверждения", "اكتب {username} للتأكيد",
  "Ketik {username} untuk konfirmasi", "確認のため {username} と入力", "확인하려면 {username} 입력")
K("accountDeleteButton", "Delete permanently", "Kalıcı olarak sil", "Eliminar para siempre", "Excluir permanentemente",
  "Endgültig löschen", "Supprimer définitivement", "Elimina per sempre", "Удалить навсегда", "حذف نهائي", "Hapus permanen",
  "完全に削除", "영구 삭제")
K("accountDeleted", "Your account was deleted.", "Hesabın silindi.", "Tu cuenta fue eliminada.", "Sua conta foi excluída.",
  "Dein Konto wurde gelöscht.", "Ton compte a été supprimé.", "Il tuo account è stato eliminato.", "Аккаунт удалён.",
  "تم حذف حسابك.", "Akunmu telah dihapus.", "アカウントを削除しました。", "계정이 삭제됐어요.")
K("accountDeleteFailed", "Couldn't delete your account: {error}", "Hesap silinemedi: {error}", "No se pudo eliminar tu cuenta: {error}",
  "Não foi possível excluir sua conta: {error}", "Konto konnte nicht gelöscht werden: {error}",
  "Impossible de supprimer ton compte : {error}", "Impossibile eliminare l'account: {error}", "Не удалось удалить аккаунт: {error}",
  "تعذّر حذف حسابك: {error}", "Gagal menghapus akun: {error}", "アカウントを削除できませんでした: {error}", "계정을 삭제하지 못했어요: {error}")

# --- Sign-up age screen (neutral: never hints at the cut-off) ---
K("ageGateTitle", "When's your birthday?", "Doğum günün ne zaman?", "¿Cuándo es tu cumpleaños?", "Quando é seu aniversário?",
  "Wann hast du Geburtstag?", "Quelle est ta date de naissance ?", "Quando sei nato?", "Когда у вас день рождения?",
  "متى عيد ميلادك؟", "Kapan ulang tahunmu?", "誕生日はいつですか？", "생일이 언제예요?")
K("ageGateBody", "It won't be shown on your profile or stored.", "Profilinde gösterilmez ve saklanmaz.",
  "No se mostrará en tu perfil ni se guardará.", "Não será exibido no seu perfil nem armazenado.",
  "Es wird weder auf deinem Profil angezeigt noch gespeichert.", "Elle ne sera ni affichée sur ton profil ni conservée.",
  "Non sarà mostrata sul profilo né salvata.", "Она не будет показана в профиле и не сохраняется.",
  "لن يظهر في ملفك الشخصي ولن يُحفظ.", "Tidak akan ditampilkan di profilmu atau disimpan.",
  "プロフィールには表示されず、保存もされません。", "프로필에 표시되지 않고 저장되지도 않아요.")
K("ageGatePick", "Select your birth date", "Doğum tarihini seç", "Selecciona tu fecha de nacimiento", "Selecione sua data de nascimento",
  "Geburtsdatum auswählen", "Choisis ta date de naissance", "Seleziona la data di nascita", "Выберите дату рождения",
  "اختر تاريخ ميلادك", "Pilih tanggal lahirmu", "生年月日を選択", "생년월일 선택")
K("ageGateTooYoungTitle", "Sorry, you can't sign up yet", "Üzgünüz, henüz kayıt olamazsın", "Lo sentimos, aún no puedes registrarte",
  "Desculpe, você ainda não pode se cadastrar", "Du kannst dich leider noch nicht registrieren",
  "Désolé, tu ne peux pas encore t'inscrire", "Spiacenti, non puoi ancora registrarti", "Извините, вы пока не можете зарегистрироваться",
  "عذرًا، لا يمكنك التسجيل بعد", "Maaf, kamu belum bisa mendaftar", "申し訳ありませんが、まだ登録できません", "죄송해요, 아직 가입할 수 없어요")
K("ageGateTooYoungBody", "You need to be at least 13 years old to use AdGag.", "AdGag'i kullanmak için en az 13 yaşında olmalısın.",
  "Necesitas tener al menos 13 años para usar AdGag.", "Você precisa ter pelo menos 13 anos para usar o AdGag.",
  "Du musst mindestens 13 Jahre alt sein, um AdGag zu nutzen.", "Tu dois avoir au moins 13 ans pour utiliser AdGag.",
  "Devi avere almeno 13 anni per usare AdGag.", "Чтобы пользоваться AdGag, вам должно быть не меньше 13 лет.",
  "يجب أن يكون عمرك 13 عامًا على الأقل لاستخدام AdGag.", "Kamu harus berusia minimal 13 tahun untuk memakai AdGag.",
  "AdGagを利用するには13歳以上である必要があります。", "AdGag를 사용하려면 만 13세 이상이어야 해요.")
