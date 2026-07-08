clc;

AGIRLIK_CARPANI = 3;

ravdessKlasoru  = fullfile(pwd, 'RAVDESS');
kisiselKlasoru  = fullfile(pwd, 'KisiselVeri');

ravdessDuygular  = {'01',    '03',    '04',    '05'};
kisiselKlasorler = {'Notr',  'Mutlu', 'Uzgun', 'Sinirli'};
etiketIsimleri   = {'Nötr',  'Mutlu', 'Üzgün', 'Sinirli'};


if ~isfolder(kisiselKlasoru)
    error('KisiselVeri klasörü bulunamadı. Önce kayit_al.m çalıştırın.');
end

fprintf('Kişisel kayıt dağılımı:\n');
toplamKisisel = 0;
for d = 1:numel(kisiselKlasorler)
    kl   = fullfile(kisiselKlasoru, kisiselKlasorler{d});
    sayi = numel(dir(fullfile(kl, '*.wav')));
    fprintf('  %-10s : %d kayıt\n', etiketIsimleri{d}, sayi);
    toplamKisisel = toplamKisisel + sayi;
end
fprintf('  TOPLAM     : %d kayıt\n\n', toplamKisisel);

if toplamKisisel < 4
    error('Çok az kişisel kayıt (%d). En az her duygudan 1 kayıt olmalı.', toplamKisisel);
end


actorKlasorleri = dir(fullfile(ravdessKlasoru, 'Actor_*'));
actorKlasorleri = actorKlasorleri([actorKlasorleri.isdir]);

tumOzellikler = [];
tumEtiketler  = {};
tumKaynak     = {};
ravdessSayac  = 0;

for a = 1:numel(actorKlasorleri)
    aktKlasor    = fullfile(ravdessKlasoru, actorKlasorleri(a).name);
    wavDosyalari = dir(fullfile(aktKlasor, '*.wav'));

    for d = 1:numel(wavDosyalari)
        dosyaAdi = wavDosyalari(d).name;
        parcalar = strsplit(dosyaAdi, '-');
        if numel(parcalar) < 3, continue; end

        duyguKodu = parcalar{3};
        if ~ismember(duyguKodu, ravdessDuygular), continue; end

        duyguIdx = find(strcmp(ravdessDuygular, duyguKodu));
        duyguAdi = etiketIsimleri{duyguIdx};

        try
            oz = extract_features(fullfile(aktKlasor, dosyaAdi));
            tumOzellikler = [tumOzellikler; oz];       %#ok<AGROW>
            tumEtiketler  = [tumEtiketler; duyguAdi];  %#ok<AGROW>
            tumKaynak     = [tumKaynak; 'ravdess'];    %#ok<AGROW>
            ravdessSayac  = ravdessSayac + 1;
            if mod(ravdessSayac, 100) == 0
                fprintf('  %d RAVDESS dosyası işlendi...\n', ravdessSayac);
            end
        catch
        end
    end
end

fprintf('  RAVDESS: %d örnek yüklendi.\n\n', ravdessSayac);

kisiselSayac = 0;

for d = 1:numel(kisiselKlasorler)
    kl           = fullfile(kisiselKlasoru, kisiselKlasorler{d});
    wavDosyalari = dir(fullfile(kl, '*.wav'));
    duyguAdi     = etiketIsimleri{d};

    for f = 1:numel(wavDosyalari)
        tamYol = fullfile(kl, wavDosyalari(f).name);
        try
            oz = extract_features(tamYol);
            for k = 1:AGIRLIK_CARPANI
                if k == 1
                    ozKlon = oz;
                else
                    gurultu = 0.02 * std(oz) .* randn(size(oz));
                    ozKlon  = oz + gurultu;
                end
                tumOzellikler = [tumOzellikler; ozKlon];   %#ok<AGROW>
                tumEtiketler  = [tumEtiketler; duyguAdi];  %#ok<AGROW>
                tumKaynak     = [tumKaynak; 'kisisel'];    %#ok<AGROW>
            end
            kisiselSayac = kisiselSayac + 1;
        catch ME
            fprintf('  UYARI: %s atlandı — %s\n', wavDosyalari(f).name, ME.message);
        end
    end
end

fprintf('  Kişisel: %d × %d = %d örnek eklendi.\n\n', ...
    kisiselSayac, AGIRLIK_CARPANI, kisiselSayac * AGIRLIK_CARPANI);


fprintf('Birleştirilmiş veri dağılımı:\n');
for s = 1:numel(etiketIsimleri)
    sayi = sum(strcmp(tumEtiketler, etiketIsimleri{s}));
    fprintf('  %-10s : %d örnek\n', etiketIsimleri{s}, sayi);
end
fprintf('  TOPLAM     : %d örnek\n\n', size(tumOzellikler, 1));


 % %80/%20 bölme

rng(42);
toplamN   = size(tumOzellikler, 1);
egitimIdx = false(toplamN, 1);
siniflar  = unique(tumEtiketler);

for s = 1:numel(siniflar)
    idx      = find(strcmp(tumEtiketler, siniflar{s}));
    karistir = idx(randperm(numel(idx)));
    egitimN  = round(0.80 * numel(idx));
    egitimIdx(karistir(1:egitimN)) = true;
end

testIdx  = ~egitimIdx;
Y        = categorical(tumEtiketler, etiketIsimleri);
X_egitim = tumOzellikler(egitimIdx, :);
Y_egitim = Y(egitimIdx);
X_test   = tumOzellikler(testIdx,   :);
Y_test   = Y(testIdx);

fprintf('Eğitim: %d | Test: %d\n\n', sum(egitimIdx), sum(testIdx));

%z-score
[X_egitimNorm, mu, sigma] = zscore(X_egitim);
sigma(sigma == 0) = 1;
X_testNorm = (X_test - mu) ./ sigma;

%destek cektör makinesi ile eğitiyoruz

svmSablonu = templateSVM( ...
    'KernelFunction', 'rbf',  ...
    'KernelScale',    'auto', ...
    'BoxConstraint',   1,     ...
    'Standardize',    false);

tic;
model = fitcecoc(X_egitimNorm, Y_egitim, ...
    'Learners',   svmSablonu,   ...
    'Coding',     'onevsone',   ...
    'ClassNames', categorical(etiketIsimleri));
sure = toc;

fprintf('Eğitim tamamlandı: %.1f sn\n', sure);

fprintf('Posterior olasılıklar kalibre ediliyor...\n');
try
    model = fitPosterior(model, X_egitimNorm, Y_egitim);
    fprintf('  Kalibrasyon başarılı ✓\n\n');
catch ME
    fprintf('  UYARI: Kalibrasyon yapılamadı — %s\n', ME.message);
    fprintf('  Güven yüzdeleri yaklaşık olacak.\n\n');
end


Y_egitimTahmin = predict(model, X_egitimNorm);
Y_testTahmin   = predict(model, X_testNorm);

egitimDogruluk = mean(Y_egitimTahmin == Y_egitim) * 100;
testDogruluk   = mean(Y_testTahmin   == Y_test)   * 100;


fprintf('  Eğitim doğruluğu : %.2f%%\n', egitimDogruluk);
fprintf('  Test  doğruluğu  : %.2f%%\n', testDogruluk);



kisiselTestMask = strcmp(tumKaynak(testIdx), 'kisisel');
if any(kisiselTestMask)
    kisiselDogr = mean(Y_testTahmin(kisiselTestMask) == Y_test(kisiselTestMask)) * 100;
    fprintf('  Kişisel kayıt doğruluğu (test): %.2f%%  (%d örnek)\n\n', ...
        kisiselDogr, sum(kisiselTestMask));
end


etiketler    = etiketIsimleri;
kayitDosyasi = fullfile(pwd, 'model.mat');

save(kayitDosyasi, 'model', 'mu', 'sigma', 'etiketler', ...
     'X_test', 'Y_test', 'X_testNorm', 'Y_testTahmin', ...
     'egitimDogruluk', 'testDogruluk');

fprintf('Yeni model kaydedildi → %s\n', kayitDosyasi);
fprintf('App Designer''ı yeniden başlatıp modeli tekrar yükle.\n\n');