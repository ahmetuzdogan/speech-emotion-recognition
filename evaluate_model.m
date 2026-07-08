clc;

kayitDosyasi = fullfile(pwd, 'model.mat');

if ~isfile(kayitDosyasi)
    error('model.mat bulunamadı. Önce train_model.m çalıştırın.');
end

fprintf('model.mat yükleniyor...\n');
yuklenmis = load(kayitDosyasi);   

model        = yuklenmis.model;
mu           = yuklenmis.mu;
sigma        = yuklenmis.sigma;
etiketler    = yuklenmis.etiketler;
X_testNorm   = yuklenmis.X_testNorm;
Y_test       = yuklenmis.Y_test;
Y_testTahmin = yuklenmis.Y_testTahmin;

fprintf('Model yüklendi. Test örnek sayısı: %d\n\n', numel(Y_test));


dogruluk = mean(Y_testTahmin == Y_test) * 100;
fprintf('Test Doğruluğu : %.2f%%\n\n', dogruluk);


siniflar = categorical(etiketler, etiketler);
nSinif   = numel(etiketler);

precision = zeros(1, nSinif);
recall    = zeros(1, nSinif);
f1Skor    = zeros(1, nSinif);

fprintf('%-10s  %-10s  %-10s  %-10s\n', 'Sınıf', 'Precision', 'Recall', 'F1-Skor');
fprintf('%s\n', repmat('-', 1, 48));

for s = 1 : nSinif
    sinif = siniflar(s);
    TP = sum(Y_testTahmin == sinif & Y_test == sinif);
    FP = sum(Y_testTahmin == sinif & Y_test ~= sinif);
    FN = sum(Y_testTahmin ~= sinif & Y_test == sinif);

    precision(s) = TP / max(TP + FP, 1);
    recall(s)    = TP / max(TP + FN, 1);
    f1Skor(s)    = 2 * precision(s) * recall(s) / max(precision(s) + recall(s), 1e-10);

    fprintf('%-10s  %-10.3f  %-10.3f  %-10.3f\n', ...
        etiketler{s}, precision(s), recall(s), f1Skor(s));
end

makroF1 = mean(f1Skor);
fprintf('%s\n', repmat('-', 1, 48));
fprintf('%-10s  %-10s  %-10s  %-10.3f\n\n', 'Makro Ort.', '', '', makroF1);


sinifRenkleri = [0.2 0.6 0.8;   % Nötr    — mavi
                 0.2 0.8 0.3;   % Mutlu   — yeşil
                 0.8 0.4 0.2;   % Üzgün   — turuncu
                 0.8 0.2 0.2];  % Sinirli — kırmızı


figure('Name', 'Confusion Matrix', 'NumberTitle', 'off', 'Position', [100 100 600 500]);

% Confusion matrix hesaplanır
nTest    = numel(Y_test);
CM       = zeros(nSinif, nSinif);

for i = 1 : nSinif
    for j = 1 : nSinif
        CM(i, j) = sum(Y_test == siniflar(i) & Y_testTahmin == siniflar(j));
    end
end

% Normalize ediyoruz
CMpct = CM ./ max(sum(CM, 2), 1) * 100;

imagesc(CMpct);
colormap(flipud(bone));
colorbar;


for i = 1 : nSinif
    for j = 1 : nSinif
        renkSec = 'k';
        if CMpct(i, j) > 50, renkSec = 'w'; end
        text(j, i, sprintf('%.1f%%\n(%d)', CMpct(i,j), CM(i,j)), ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'middle', ...
            'FontSize', 11, 'FontWeight', 'bold', 'Color', renkSec);
    end
end

xticks(1:nSinif);  xticklabels(etiketler);
yticks(1:nSinif);  yticklabels(etiketler);
xlabel('Tahmin Edilen Sınıf', 'FontSize', 12);
ylabel('Gerçek Sınıf',        'FontSize', 12);
title(sprintf('Confusion Matrix — Test Doğruluğu: %.2f%%', dogruluk), 'FontSize', 14);


figure('Name', 'F1 Skoru', 'NumberTitle', 'off', 'Position', [720 100 500 400]);

bar_h = bar(1:nSinif, f1Skor, 0.6);
bar_h.FaceColor = 'flat';
for s = 1 : nSinif
    bar_h.CData(s, :) = sinifRenkleri(s, :);
end

ylim([0 1.1]);
xticks(1:nSinif);  xticklabels(etiketler);
xlabel('Duygu Sınıfı',  'FontSize', 12);
ylabel('F1 Skoru',       'FontSize', 12);
title('Sınıf Bazında F1 Skoru', 'FontSize', 14);
grid on;


for s = 1 : nSinif
    text(s, f1Skor(s) + 0.02, sprintf('%.3f', f1Skor(s)), ...
        'HorizontalAlignment', 'center', 'FontSize', 11, 'FontWeight', 'bold');
end

figure('Name', 'Özellik Dağılımı', 'NumberTitle', 'off', 'Position', [100 550 1000 420]);

X_test_raw = yuklenmis.X_test;


subplot(1, 2, 1);
hold on;
for s = 1 : nSinif
    maske = (Y_test == siniflar(s));
    scatter(X_test_raw(maske, 1), X_test_raw(maske, 2), 40, ...
        sinifRenkleri(s, :), 'filled', 'MarkerFaceAlpha', 0.7, ...
        'DisplayName', etiketler{s});
end
hold off;
xlabel('MFCC 1 (Ortalama)',  'FontSize', 11);
ylabel('MFCC 2 (Ortalama)',  'FontSize', 11);
title('MFCC1 vs MFCC2 — Sınıf Dağılımı', 'FontSize', 13);
legend('Location', 'best', 'FontSize', 10);
grid on;


subplot(1, 2, 2);
hold on;
for s = 1 : nSinif
    maske = (Y_test == siniflar(s));
    scatter(X_test_raw(maske, 15), X_test_raw(maske, 16), 40, ...
        sinifRenkleri(s, :), 'filled', 'MarkerFaceAlpha', 0.7, ...
        'DisplayName', etiketler{s});
end
hold off;
xlabel('ZCR (Sıfır Geçiş Hızı)',     'FontSize', 11);
ylabel('Spektral Merkez (Hz)',         'FontSize', 11);
title('ZCR vs Spektral Merkez — Sınıf Dağılımı', 'FontSize', 13);
legend('Location', 'best', 'FontSize', 10);
grid on;

% -------------------------------------------------------------------------
% Şekil 4 — t-SNE Görselleştirmesi (Statistics and ML Toolbox gerekir)
% -------------------------------------------------------------------------
try
    fprintf('t-SNE hesaplanıyor (bu biraz sürebilir)...\n');
    rng(42);
    tsneKoor = tsne(X_testNorm, 'Algorithm', 'exact', 'NumDimensions', 2);

    figure('Name', 't-SNE Özellik Uzayı', 'NumberTitle', 'off', 'Position', [620 550 600 500]);
    hold on;
    for s = 1 : nSinif
        maske = (Y_test == siniflar(s));
        scatter(tsneKoor(maske, 1), tsneKoor(maske, 2), 50, ...
            sinifRenkleri(s, :), 'filled', 'MarkerFaceAlpha', 0.8, ...
            'DisplayName', etiketler{s});
    end
    hold off;
    xlabel('t-SNE Boyut 1', 'FontSize', 12);
    ylabel('t-SNE Boyut 2', 'FontSize', 12);
    title('t-SNE — Özellik Uzayında Duygu Kümeleri', 'FontSize', 14);
    legend('Location', 'best', 'FontSize', 11);
    grid on;
    fprintf('t-SNE grafiği oluşturuldu.\n');
catch ME
    fprintf('UYARI: t-SNE çizilemedi — %s\n', ME.message);
end

fprintf('\nDeğerlendirme tamamlandı.\n');
fprintf('Sıradaki adım: DuyguTanima.mlapp arayüzünü çalıştır.\n');
