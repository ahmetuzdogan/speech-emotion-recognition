clc;

ravdessKlasoru = fullfile(pwd, 'RAVDESS'); 

if ~isfolder(ravdessKlasoru)
    error(['RAVDESS klasörü bulunamadı: %s\n' ...
           'Lütfen RAVDESS klasörünü bu betikle aynı dizine koyun.'], ravdessKlasoru);
end


actorKlasorleri = dir(fullfile(ravdessKlasoru, 'Actor_*'));
actorKlasorleri = actorKlasorleri([actorKlasorleri.isdir]);  
if isempty(actorKlasorleri)
    error('RAVDESS içinde Actor_XX klasörü bulunamadı.');
end

fprintf('Toplam aktör klasörü: %d\n\n', numel(actorKlasorleri));


hedefDuygular = {'01', '03', '04', '05'};
etiketIsimleri = {'Nötr', 'Mutlu', 'Üzgün', 'Sinirli'};


tumOzellikler = [];   % [N × 16]
tumEtiketler  = {};   % N × 1 


toplamDosya = 0;
atlalanDosya = 0;

for a = 1 : numel(actorKlasorleri)
    aktKlasor = fullfile(ravdessKlasoru, actorKlasorleri(a).name);
    wavDosyalari = dir(fullfile(aktKlasor, '*.wav'));

    for d = 1 : numel(wavDosyalari)
        dosyaAdi = wavDosyalari(d).name;

        
        parcalar = strsplit(dosyaAdi, '-');

        
        if numel(parcalar) < 3
            atlalanDosya = atlalanDosya + 1;
            continue;
        end

        duyguKodu = parcalar{3};

        
        if ~ismember(duyguKodu, hedefDuygular)
            continue;
        end

        % Duygu adını bul
        duyguIdx  = find(strcmp(hedefDuygular, duyguKodu));
        duyguAdi  = etiketIsimleri{duyguIdx};

        % Özellik çıkar
        dosyaTamYol = fullfile(aktKlasor, dosyaAdi);
        try
            ozellik = extract_features(dosyaTamYol);   
            tumOzellikler = [tumOzellikler; ozellik];  %#ok<AGROW>
            tumEtiketler  = [tumEtiketler; duyguAdi];  %#ok<AGROW>
            toplamDosya   = toplamDosya + 1;

            if mod(toplamDosya, 50) == 0
                fprintf('  %d dosya işlendi...\n', toplamDosya);
            end
        catch ME
            fprintf('  UYARI: %s atlandı — %s\n', dosyaAdi, ME.message);
            atlalanDosya = atlalanDosya + 1;
        end
    end
end

fprintf('\nToplam işlenen dosya : %d\n', toplamDosya);
fprintf('Atlanan  dosya       : %d\n\n', atlalanDosya);

if toplamDosya < 10
    error('Yeterli veri yok (sadece %d örnek). Klasör yapısını kontrol edin.', toplamDosya);
end

% Sınıf dağılımını göster
siniflar = unique(tumEtiketler);
fprintf('Sınıf dağılımı:\n');
for s = 1 : numel(siniflar)
    sayi = sum(strcmp(tumEtiketler, siniflar{s}));
    fprintf('  %-10s : %d örnek\n', siniflar{s}, sayi);
end
fprintf('\n');


Y = categorical(tumEtiketler, etiketIsimleri);   


% Veri setini %80-%20 böleriz

rng(42); 

egitimIdx = false(toplamDosya, 1);

for s = 1 : numel(siniflar)
    sinifMask   = strcmp(tumEtiketler, siniflar{s});
    sinifIdxler = find(sinifMask);
    sinifBoy    = numel(sinifIdxler);
    karistir    = sinifIdxler(randperm(sinifBoy));
    egitimSayisi = round(0.80 * sinifBoy);
    egitimIdx(karistir(1 : egitimSayisi)) = true;
end

testIdx = ~egitimIdx;

X_egitim = tumOzellikler(egitimIdx, :);
Y_egitim = Y(egitimIdx);
X_test   = tumOzellikler(testIdx,   :);
Y_test   = Y(testIdx);

fprintf('Eğitim seti : %d örnek\n', sum(egitimIdx));
fprintf('Test seti   : %d örnek\n', sum(testIdx));
fprintf('\n');


% Z-Score Test seti aynı parametrelerle normalize edilir (data leakage önlenir).

[X_egitimNorm, mu, sigma] = zscore(X_egitim);


sigma(sigma == 0) = 1;

%normalizasyon  yapıyoruz
X_testNorm = (X_test - mu) ./ sigma;

fprintf('Z-Score normalizasyon uygulandı.\n');
fprintf('Özellik boyutu: %d\n\n', size(X_egitimNorm, 2));

%desktek vektör makinesi ve fitcecoc ile modeli eğitiyorum

svmSablonu = templateSVM( ...
    'KernelFunction',    'rbf',   ...
    'KernelScale',       'auto',  ...
    'BoxConstraint',     1,       ...
    'Standardize',       false);  

tic;
model = fitcecoc(X_egitimNorm, Y_egitim, ...
    'Learners',   svmSablonu,   ...
    'Coding',     'onevsone',   ...
    'ClassNames', categorical(etiketIsimleri));
egitimSuresi = toc;

fprintf('Eğitim tamamlandı: %.1f saniye\n\n', egitimSuresi);


Y_egitimTahmin = predict(model, X_egitimNorm);
Y_testTahmin   = predict(model, X_testNorm);

egitimDogruluk = mean(Y_egitimTahmin == Y_egitim) * 100;
testDogruluk   = mean(Y_testTahmin   == Y_test)   * 100;

fprintf('  Eğitim doğruluğu : %.2f%%\n', egitimDogruluk);
fprintf('  Test  doğruluğu  : %.2f%%\n', testDogruluk);


etiketler = etiketIsimleri;

kayitDosyasi = fullfile(pwd, 'model.mat');
save(kayitDosyasi, 'model', 'mu', 'sigma', 'etiketler', ...
     'X_test', 'Y_test', 'X_testNorm', 'Y_testTahmin', ...
     'egitimDogruluk', 'testDogruluk');

fprintf('Model kaydedildi → %s\n', kayitDosyasi);
fprintf('\nSıradaki adım: evaluate_model.m\n');
