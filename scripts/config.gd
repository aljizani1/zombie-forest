# ════════ إعدادات اللعبة ════════
# كل الأرقام هنا تگدر تغيّرها: الساحة، المراحل، الزومبي، الأسلحة.
extends Node

const AH := 720.0 # طول العالم
const GRAVITY := 2600.0

# ── اللاعب ──
const PLAYER := {hp = 100, speed = 330.0, jump = 1100.0, w = 44.0, h = 128.0}

# ── الأسلحة (الطلق لا نهائي) ──
# rate = الوقت بين طلقة وطلقة، mag = طلقات المخزن، reload = وقت سحب مخزن جديد
const WEAPONS := {
	"pistol": {name = "مسدس", damage = 2.0, rate = 0.3, speed = 1700.0, spread = 0.0, price = 0, mag = 12, reload = 1.4},
	"akm": {name = "AKM", damage = 2.0, rate = 0.1, speed = 2000.0, spread = 8.0, price = 250, mag = 30, reload = 2.3},
	"pkm": {name = "PKC", damage = 3.0, rate = 0.075, speed = 2200.0, spread = 11.0, price = 700, mag = 100, reload = 3.8},
}
const GUN_ORDER := ["pistol", "akm", "pkm"]

# ── الرمانات ──
const GRENADE := {per_stage = 5, cooldown = 0.9, fuse = 1.6, radius = 190.0, damage = 14.0, throw_x = 560.0, throw_y = 720.0}

# ── أنواع الزومبي ──
# head = نسبة الراس من فوگ (للهيدشوت)
const ZOMBIES := {
	"walker": {hp = 6.0, speed = [70.0, 105.0], damage = 8, coins = 5, jumpy = 0.5, scale = 1.0, head = 0.24},
	"runner": {hp = 4.0, speed = [170.0, 215.0], damage = 6, coins = 7, jumpy = 0.8, scale = 0.95, head = 0.24},
	"tough": {hp = 16.0, speed = [90.0, 125.0], damage = 12, coins = 10, jumpy = 1.0, scale = 1.06, head = 0.24},
	"flyer": {hp = 8.0, speed = [55.0, 75.0], damage = 10, coins = 12, jumpy = 0.0, scale = 0.95, head = 0.3},
	"brute": {hp = 60.0, speed = [50.0, 65.0], damage = 25, coins = 40, jumpy = 0.0, scale = 1.4, head = 0.22},
	"monster": {hp = 110.0, speed = [60.0, 80.0], damage = 32, coins = 90, jumpy = 0.3, scale = 1.0, size = [86.0, 160.0], head = 0.3},
}

const HEADSHOT := 3.0 # ضرر الهيدشوت × 3
const HP_PER_STAGE := 0.07 # الزومبي يصير أقوى 7% كل مرحلة
const CLEAR_BONUS := 25 # مكافأة إنهاء المرحلة × رقمها

# ── المراحل (15) ──
# total = عدد الزومبي الكلي، max_alive = كم واحد بنفس الوقت، every = كل كم ثانية يطلع واحد
const STAGES := [
	{total = 12, max_alive = 5, every = [1.3, 2.2], mix = {walker = 1.0}},
	{total = 18, max_alive = 6, every = [1.0, 1.8], mix = {walker = 0.8, tough = 0.2}},
	{total = 24, max_alive = 8, every = [0.9, 1.5], mix = {walker = 0.55, tough = 0.35, runner = 0.1}},
	{total = 30, max_alive = 9, every = [0.8, 1.4], mix = {walker = 0.4, tough = 0.4, runner = 0.1, flyer = 0.1}},
	{total = 36, max_alive = 10, every = [0.7, 1.3], mix = {walker = 0.3, tough = 0.4, runner = 0.15, flyer = 0.15}},
	{total = 42, max_alive = 11, every = [0.65, 1.2], mix = {walker = 0.25, tough = 0.4, runner = 0.15, flyer = 0.12, brute = 0.08}},
	{total = 48, max_alive = 12, every = [0.6, 1.1], mix = {walker = 0.2, tough = 0.4, runner = 0.18, flyer = 0.14, brute = 0.08}},
	{total = 55, max_alive = 13, every = [0.55, 1.0], mix = {walker = 0.15, tough = 0.42, runner = 0.18, flyer = 0.15, brute = 0.1}},
	{total = 62, max_alive = 14, every = [0.5, 0.95], mix = {walker = 0.1, tough = 0.42, runner = 0.2, flyer = 0.16, brute = 0.12}},
	{total = 70, max_alive = 15, every = [0.45, 0.9], mix = {walker = 0.04, tough = 0.4, runner = 0.2, flyer = 0.16, brute = 0.14, monster = 0.06}},
	{total = 78, max_alive = 16, every = [0.42, 0.85], mix = {walker = 0.02, tough = 0.38, runner = 0.2, flyer = 0.17, brute = 0.15, monster = 0.08}},
	{total = 86, max_alive = 17, every = [0.4, 0.8], mix = {tough = 0.36, runner = 0.2, flyer = 0.18, brute = 0.16, monster = 0.1}},
	{total = 95, max_alive = 18, every = [0.38, 0.75], mix = {tough = 0.34, runner = 0.2, flyer = 0.18, brute = 0.16, monster = 0.12}},
	{total = 105, max_alive = 19, every = [0.35, 0.7], mix = {tough = 0.32, runner = 0.2, flyer = 0.18, brute = 0.16, monster = 0.14}},
	{total = 120, max_alive = 20, every = [0.32, 0.65], mix = {tough = 0.3, runner = 0.2, flyer = 0.18, brute = 0.16, monster = 0.16}},
]
