-- ============================================================================
-- SQL SETUP & ROW LEVEL SECURITY (RLS) UNTUK APLIKASI PRESENSI WAJAH & GPS
-- Jalankan seluruh script ini di menu "SQL Editor" pada Dashboard Supabase Anda
-- ============================================================================

-- Aktifkan ekstensi UUID jika belum aktif
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. TABEL KONFIGURASI SISTEM & GEOFENCING SEKOLAH (system_settings)
CREATE TABLE IF NOT EXISTS public.system_settings (
    id BIGINT PRIMARY KEY DEFAULT 1,
    app_name TEXT NOT NULL DEFAULT 'Gercep Asik',
    app_subtitle TEXT NOT NULL DEFAULT 'Masuk untuk melanjutkan ke layanan kepegawaian.',
    logo_url TEXT DEFAULT '',
    office_name TEXT NOT NULL DEFAULT 'Kantor Dinas Pendidikan',
    latitude DOUBLE PRECISION NOT NULL DEFAULT -6.937222,
    longitude DOUBLE PRECISION NOT NULL DEFAULT 107.597542,
    radius_meters INTEGER NOT NULL DEFAULT 40,
    weekly_schedule JSONB NOT NULL DEFAULT '[
      {"day":"Senin","is_holiday":false,"in_start":"07:00","in_end":"08:00","out_start":"16:00","out_end":"18:00"},
      {"day":"Selasa","is_holiday":false,"in_start":"07:00","in_end":"08:00","out_start":"16:00","out_end":"18:00"},
      {"day":"Rabu","is_holiday":false,"in_start":"07:00","in_end":"08:00","out_start":"16:00","out_end":"18:00"},
      {"day":"Kamis","is_holiday":false,"in_start":"07:00","in_end":"08:00","out_start":"16:00","out_end":"18:00"},
      {"day":"Jumat","is_holiday":false,"in_start":"07:00","in_end":"08:00","out_start":"16:30","out_end":"18:00"},
      {"day":"Sabtu","is_holiday":true,"in_start":"08:00","in_end":"09:00","out_start":"13:00","out_end":"15:00"},
      {"day":"Minggu","is_holiday":true,"in_start":"08:00","in_end":"09:00","out_start":"13:00","out_end":"15:00"}
    ]'::jsonb,
    is_maintenance BOOLEAN NOT NULL DEFAULT FALSE,
    maintenance_message TEXT DEFAULT 'Sistem sedang dalam pemeliharaan berkala untuk peningkatan layanan.',
    kop_logo_url TEXT DEFAULT '',
    headmaster_name TEXT DEFAULT '',
    headmaster_nip TEXT DEFAULT '',
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Migrasi aman: Pastikan kolom-kolom baru tetap ditambahkan jika tabel system_settings sudah dibuat sebelumnya
ALTER TABLE public.system_settings ADD COLUMN IF NOT EXISTS is_maintenance BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.system_settings ADD COLUMN IF NOT EXISTS maintenance_message TEXT DEFAULT 'Sistem sedang dalam pemeliharaan berkala untuk peningkatan layanan.';
ALTER TABLE public.system_settings ADD COLUMN IF NOT EXISTS kop_logo_url TEXT DEFAULT '';
ALTER TABLE public.system_settings ADD COLUMN IF NOT EXISTS headmaster_name TEXT DEFAULT '';
ALTER TABLE public.system_settings ADD COLUMN IF NOT EXISTS headmaster_nip TEXT DEFAULT '';
ALTER TABLE public.system_settings ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Insert 1 baris konfigurasi awal jika belum ada
INSERT INTO public.system_settings (
    id,
    app_name,
    app_subtitle,
    office_name,
    latitude,
    longitude,
    radius_meters,
    is_maintenance,
    maintenance_message,
    kop_logo_url,
    headmaster_name,
    headmaster_nip
)
VALUES (
    1,
    'Gercep Asik',
    'Masuk untuk melanjutkan ke layanan kepegawaian.',
    'Kantor Dinas Pendidikan',
    -6.937222,
    107.597542,
    40,
    FALSE,
    'Sistem sedang dalam pemeliharaan berkala untuk peningkatan layanan.',
    '',
    '',
    ''
)
ON CONFLICT (id) DO NOTHING;

-- 2. TABEL HARI LIBUR KHUSUS / NASIONAL (holidays)
CREATE TABLE IF NOT EXISTS public.holidays (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    holiday_date DATE NOT NULL UNIQUE,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. TABEL DATA GURU / PEGAWAI UNTUK HYBRID LOGIN & BIOMETRIK (teachers)
CREATE TABLE IF NOT EXISTS public.teachers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nip TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL UNIQUE,
    password TEXT NOT NULL,
    full_name TEXT NOT NULL,
    position TEXT DEFAULT 'Guru Mata Pelajaran',
    face_registered BOOLEAN NOT NULL DEFAULT FALSE,
    face_photo_url TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. TABEL RIWAYAT PRESENSI HARIAN (attendances)
CREATE TABLE IF NOT EXISTS public.attendances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID NOT NULL REFERENCES public.teachers(id) ON DELETE CASCADE,
    attendance_date DATE NOT NULL DEFAULT CURRENT_DATE,
    check_in_time TEXT,
    check_out_time TEXT,
    work_duration TEXT,
    status TEXT NOT NULL DEFAULT 'Masuk',
    notes TEXT DEFAULT '1x presensi',
    lat_in DOUBLE PRECISION,
    lng_in DOUBLE PRECISION,
    distance_meters INTEGER DEFAULT 0,
    face_score NUMERIC(5,2) DEFAULT 98.50,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. TABEL PENGAJUAN DINAS LUAR, WFA/H, & IZIN/SAKIT (leave_requests)
CREATE TABLE IF NOT EXISTS public.leave_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID NOT NULL REFERENCES public.teachers(id) ON DELETE CASCADE,
    request_type TEXT NOT NULL DEFAULT 'Dinas Luar',
    request_date DATE NOT NULL DEFAULT CURRENT_DATE,
    duration_type TEXT NOT NULL DEFAULT 'Full',
    description TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'Menunggu',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. TABEL PENGUMUMAN & PESAN KEPEGAWAIAN (announcements)
CREATE TABLE IF NOT EXISTS public.announcements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    priority TEXT NOT NULL DEFAULT 'Info Umum',
    created_by TEXT DEFAULT 'Administrator',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- KONFIGURASI ROW LEVEL SECURITY (RLS) UNTUK ARSITEKTUR HYBRID LOGIN
-- Mengizinkan role `authenticated` (Admin via Supabase Auth) dan role `anon`
-- (Guru via validasi tabel database) untuk berinteraksi tanpa kendala RLS.
-- ============================================================================

ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.holidays ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teachers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

-- Kebijakan untuk system_settings
DROP POLICY IF EXISTS "Allow full access to system_settings" ON public.system_settings;
CREATE POLICY "Allow full access to system_settings"
ON public.system_settings FOR ALL
TO anon, authenticated
USING (true)
WITH CHECK (true);

-- Kebijakan untuk holidays
DROP POLICY IF EXISTS "Allow full access to holidays" ON public.holidays;
CREATE POLICY "Allow full access to holidays"
ON public.holidays FOR ALL
TO anon, authenticated
USING (true)
WITH CHECK (true);

-- Kebijakan untuk teachers
DROP POLICY IF EXISTS "Allow full access to teachers" ON public.teachers;
CREATE POLICY "Allow full access to teachers"
ON public.teachers FOR ALL
TO anon, authenticated
USING (true)
WITH CHECK (true);

-- Kebijakan untuk attendances
DROP POLICY IF EXISTS "Allow full access to attendances" ON public.attendances;
CREATE POLICY "Allow full access to attendances"
ON public.attendances FOR ALL
TO anon, authenticated
USING (true)
WITH CHECK (true);

-- Kebijakan untuk leave_requests
DROP POLICY IF EXISTS "Allow full access to leave_requests" ON public.leave_requests;
CREATE POLICY "Allow full access to leave_requests"
ON public.leave_requests FOR ALL
TO anon, authenticated
USING (true)
WITH CHECK (true);

-- Kebijakan untuk announcements
DROP POLICY IF EXISTS "Allow full access to announcements" ON public.announcements;
CREATE POLICY "Allow full access to announcements"
ON public.announcements FOR ALL
TO anon, authenticated
USING (true)
WITH CHECK (true);
