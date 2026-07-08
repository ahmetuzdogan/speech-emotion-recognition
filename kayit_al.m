% KAYIT_AL  Her duygu için kişisel ses örnekleri kaydeder.
%
% Kullanım:
%   kayit_al          % Varsayılan: her duygudan 25 kayıt
%   kayit_al(10)      % Her duygudan 10 kayıt (hızlı test için)
%
% Çıktı klasörü:
%   ./KisiselVeri/Notr/
%   ./KisiselVeri/Mutlu/
%   ./KisiselVeri/Uzgun/
%   ./KisiselVeri/Sinirli/
%
% Kayıt sonunda retrain_personal.m ile modeli yeniden eğit.

function kayit_al(ornekSayisi)

if nargin < 1
    ornekSayisi = 25;   % Her duygu için varsayılan kayıt sayısı
end

% -------------------------------------------------------------------------
% Parametreler
% -------------------------------------------------------------------------
ORNEK_HIZI   = 22050;   % Hz — extract_features ile uyumlu
KAYIT_SURESI = 3;       % Saniye
BIT_DERINLIGI = 16;

% -------------------------------------------------------------------------
% Söylenecek cümleler — duyguya göre
% -------------------------------------------------------------------------
% Her listedeki cümleleri sırayla söylersin.
% ornekSayisi > cümle sayısı ise cümleler tekrar eder.
cumleler = struct();

cumleler.Notr = {
    'Bugün hava güzel.'
    'Kapıyı kapatır mısın?'
    'Toplantı saat üçte başlıyor.'
    'Bu kitabı dün aldım.'
    'Yarın işe erken gideceğim.'
    'Ekranı biraz sola taşı lütfen.'
    'Kahvem soğudu.'
    'Otobüs beş dakika sonra geliyor.'
    'Bu formu doldurmam gerekiyor.'
    'Şifrenizi unutmayın.'
};

cumleler.Mutlu = {
    'Harika, sonunda bitti!'
    'Seni görmek çok güzel!'
    'Bu haberi duyunca çok sevindim!'
    'Mükemmel bir gün geçirdim!'
    'En iyi günüm bugün!'
    'Bunu başardım, inanamıyorum!'
    'Ne kadar güzel bir sürpriz!'
    'Çok mutluyum, gerçekten!'
    'Harika hissediyorum!'
    'Bu sonuç beni çok mutlu etti!'
};

cumleler.Uzgun = {
    'Çok üzgünüm, gerçekten zor.'
    'Bir daha göremeyeceğim onu.'
    'Her şey çok kötü gidiyor.'
    'Kendimi çok yalnız hissediyorum.'
    'Bunu duymak istemezdim.'
    'Neden böyle oldu, anlayamıyorum.'
    'Çok yorgunum, devam edemiyorum.'
    'Hepsi geçti, artık eskisi gibi değil.'
    'Çok zor bir dönemden geçiyorum.'
    'Hiç bu kadar kötü hissetmemiştim.'
};

cumleler.Sinirli = {
    'Bu kadar saçmalık olmaz!'
    'Kaç kez söylemem gerekiyor?'
    'Yeter artık, bıktım!'
    'Neden kimse dinlemiyor beni?'
    'Bu durum kabul edilemez!'
    'Her seferinde aynı hata!'
    'Bunu neden hâlâ anlamıyorsun?'
    'Çok sinir bozucu bir durum bu!'
    'Artık dayanamıyorum!'
    'Bu işi mahvettiniz!'
};

% -------------------------------------------------------------------------
% Klasörleri oluştur
% -------------------------------------------------------------------------
duygular     = {'Notr', 'Mutlu', 'Uzgun', 'Sinirli'};
duyguGoster  = {'😐 Nötr', '😊 Mutlu', '😢 Üzgün', '😠 Sinirli'};
kokKlasor    = fullfile(pwd, 'KisiselVeri');

for d = 1 : numel(duygular)
    klasor = fullfile(kokKlasor, duygular{d});
    if ~isfolder(klasor)
        mkdir(klasor);
    end
end

% -------------------------------------------------------------------------
% Mevcut kayıt sayılarını öğren (kaldığı yerden devam)
% -------------------------------------------------------------------------
fprintf('\n============================================================\n');
fprintf('  Kişisel Veri Seti Kaydı\n');
fprintf('  Her duygu için %d kayıt alınacak (%d sn/kayıt)\n', ornekSayisi, KAYIT_SURESI);
fprintf('============================================================\n\n');
fprintf('  Hazır olduğunda Enter''a bas. İstediğin zaman Ctrl+C ile dur.\n');
fprintf('  Kaldığın yerden devam edebilirsin.\n\n');
input('  Başlamak için Enter''a bas...', 's');

% -------------------------------------------------------------------------
% Her duygu için kayıt döngüsü
% -------------------------------------------------------------------------
for d = 1 : numel(duygular)
    duygu    = duygular{d};
    klasor   = fullfile(kokKlasor, duygu);

    % Mevcut kayıt sayısını bul
    mevcutlar   = dir(fullfile(klasor, '*.wav'));
    baslangic   = numel(mevcutlar) + 1;
    hedef       = ornekSayisi;

    if baslangic > hedef
        fprintf('\n%s — Zaten %d kayıt var, atlanıyor.\n', duyguGoster{d}, numel(mevcutlar));
        continue;
    end

    fprintf('\n============================================================\n');
    fprintf('  %s  (%d / %d kayıt tamamlandı)\n', duyguGoster{d}, baslangic-1, hedef);
    fprintf('============================================================\n');

    % Duygu için ipuçları
    fprintf('  İpucu: ');
    switch duygu
        case 'Notr'
            fprintf('Düz, sakin, duygusuz bir sesle konuş.\n');
        case 'Mutlu'
            fprintf('Neşeli, enerjik, gülümseyen bir sesle konuş.\n');
        case 'Uzgun'
            fprintf('Yavaş, kırık, içine çökmüş bir sesle konuş.\n');
        case 'Sinirli'
            fprintf('Sert, gergin, yüksek tonlu bir sesle konuş.\n');
    end
    fprintf('\n');

    cumleListesi = cumleler.(duygu);
    cumleIdx     = mod(baslangic - 1, numel(cumleListesi));   % kaldığı cümleden devam

    for k = baslangic : hedef
        cumleIdx = mod(cumleIdx, numel(cumleListesi)) + 1;
        cumle    = cumleListesi{cumleIdx};

        fprintf('  [%2d/%d]  "%s"\n', k, hedef, cumle);
        fprintf('         3 sn içinde söyle — hazırlanmak için 1 sn bekleniyor...\n');

        pause(1.0);   % Hazırlık süresi

        fprintf('         >>> KAYIT BAŞLIYOR (%d sn) <<<\n', KAYIT_SURESI);

        try
            kaydedici = audiorecorder(ORNEK_HIZI, BIT_DERINLIGI, 1);
            recordblocking(kaydedici, KAYIT_SURESI);
            y = getaudiodata(kaydedici);
        catch ME
            fprintf('         HATA: %s\n', ME.message);
            fprintf('         Mikrofon bağlı mı? Bu kaydı atlıyorum.\n');
            continue;
        end

        % Sessizlik kontrolü — RMS < eşik ise uyar
        rmsGuc = sqrt(mean(y.^2));
        if rmsGuc < 0.001
            fprintf('         ⚠  Ses çok sessiz (RMS=%.4f). Mikrofonunu kontrol et.\n', rmsGuc);
            fprintf('         Bu kaydı yine de kaydediyorum — istersen sil.\n');
        end

        % Dosyayı kaydet
        dosyaAdi = sprintf('%s_%03d.wav', duygu, k);
        tamYol   = fullfile(klasor, dosyaAdi);
        audiowrite(tamYol, y, ORNEK_HIZI);

        fprintf('         ✓ Kaydedildi: %s\n\n', dosyaAdi);

        % Her 5 kayıtta bir mola teklif et
        if mod(k, 5) == 0 && k < hedef
            fprintf('  --- 5 kayıt tamamlandı. Devam etmek için Enter, atlamak için S+Enter ---\n');
            cevap = input('  ', 's');
            if strcmpi(strtrim(cevap), 'S')
                fprintf('  %s atlandı.\n', duygu);
                break;
            end
        end
    end

    fprintf('\n  %s tamamlandı ✓\n', duyguGoster{d});
end

% -------------------------------------------------------------------------
% Özet
% -------------------------------------------------------------------------
fprintf('\n============================================================\n');
fprintf('  Kayıt Özeti\n');
fprintf('============================================================\n');

toplamKayit = 0;
for d = 1 : numel(duygular)
    klasor  = fullfile(kokKlasor, duygular{d});
    dosyalar = dir(fullfile(klasor, '*.wav'));
    sayi     = numel(dosyalar);
    toplamKayit = toplamKayit + sayi;
    fprintf('  %-10s : %d kayıt\n', duygular{d}, sayi);
end

fprintf('  %-10s : %d kayıt\n', 'TOPLAM', toplamKayit);
fprintf('\nSıradaki adım:\n');
fprintf('  >> retrain_personal\n\n');

end
