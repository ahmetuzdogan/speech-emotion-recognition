classdef DuyguTanima < matlab.apps.AppBase

    % =====================================================================
    % DuyguTanima.mlapp  —  v2
    %
    % Yenilikler:
    %   - Her sınıf için güven yüzdesi + renkli çubuk göstergesi
    %   - 42 özellikli extract_features ile uyumlu
    %   - fitPosterior ile kalibre edilmiş olasılıklar
    % =====================================================================

    properties (Access = public)
        UIFigure          matlab.ui.Figure

        % Panel 1 — Model
        PanelModel        matlab.ui.container.Panel
        BtnModelYukle     matlab.ui.control.Button
        LblModelDurum     matlab.ui.control.Label

        % Panel 2 — Ses Girişi
        PanelSes          matlab.ui.container.Panel
        BtnDosyaSec       matlab.ui.control.Button
        BtnMikrofon       matlab.ui.control.Button
        LblDosyaAdi       matlab.ui.control.Label

        % Panel 3 — Sonuç
        PanelSonuc        matlab.ui.container.Panel
        BtnAnalizEt       matlab.ui.control.Button
        LblDuygu          matlab.ui.control.Label   % Büyük duygu etiketi

        % Güven yüzdesi — her sınıf için etiket + eksen
        LblGuven          matlab.ui.control.Label   % "Güven Dağılımı" başlık
        AxesGuven         matlab.ui.control.UIAxes  % Yatay çubuk grafik

        % Grafikler
        AxesWaveform      matlab.ui.control.UIAxes
        AxesMFCC          matlab.ui.control.UIAxes
    end

    properties (Access = private)
        Model           % fitcecoc modeli
        Mu
        Sigma
        Etiketler
        ModelYuklendi   logical = false

        SesVerisi
        OrnekHizi
        DosyaYolu

        % Renk paleti (sınıf sırasına göre: Nötr Mutlu Üzgün Sinirli)
        SinifRenkleri = [0.2 0.5 0.8;
                         0.1 0.7 0.2;
                         0.8 0.5 0.1;
                         0.8 0.1 0.1];
    end

    % ==================================================================
    % CALLBACK FONKSİYONLARI
    % ==================================================================
    methods (Access = private)

        % ----------------------------------------------------------
        % "Modeli Yükle" butonu
        % ----------------------------------------------------------
        function BtnModelYukleCallback(app, ~)
            [dosyaAdi, klasor] = uigetfile('*.mat', 'model.mat Seçin');
            if isequal(dosyaAdi, 0), return; end

            try
                veri = load(fullfile(klasor, dosyaAdi));
                gerekli = {'model','mu','sigma','etiketler'};
                for k = 1:numel(gerekli)
                    if ~isfield(veri, gerekli{k})
                        error('"%s" alanı bulunamadı.', gerekli{k});
                    end
                end
                app.Model         = veri.model;
                app.Mu            = veri.mu;
                app.Sigma         = veri.sigma;
                app.Etiketler     = veri.etiketler;
                app.ModelYuklendi = true;

                app.LblModelDurum.Text      = '✓ Model yüklendi';
                app.LblModelDurum.FontColor = [0.1 0.6 0.1];

                % Güven eksenini hazırla
                app.guvenEkseniniHazirla();

            catch ME
                app.ModelYuklendi = false;
                app.LblModelDurum.Text      = '✗ Model yüklenemedi';
                app.LblModelDurum.FontColor = [0.8 0.1 0.1];
                uialert(app.UIFigure, sprintf('Hata:\n%s', ME.message), 'Hata', 'Icon','error');
            end
        end

        % ----------------------------------------------------------
        % "Ses Dosyası Seç" butonu
        % ----------------------------------------------------------
        function BtnDosyaSecCallback(app, ~)
            [dosyaAdi, klasor] = uigetfile({'*.wav','WAV (*.wav)'}, 'Ses Dosyası Seç');
            if isequal(dosyaAdi, 0), return; end

            try
                [y, fs] = audioread(fullfile(klasor, dosyaAdi));
                if size(y,2) > 1, y = mean(y,2); end
                app.SesVerisi = y;
                app.OrnekHizi = fs;
                app.DosyaYolu = fullfile(klasor, dosyaAdi);
                app.LblDosyaAdi.Text = sprintf('📁 %s', dosyaAdi);
                app.cizWaveform();
                app.temizleMFCC();
                app.sifirlaGosterge();
            catch ME
                uialert(app.UIFigure, sprintf('Dosya okunamadı:\n%s', ME.message), 'Hata', 'Icon','error');
            end
        end

        % ----------------------------------------------------------
        % "Mikrofon ile Kaydet" butonu
        % ----------------------------------------------------------
        function BtnMikofonCallback(app, ~)
            SURE = 3; FS = 22050;
            try
                app.BtnMikrofon.Text   = '🔴 Kaydediliyor...';
                app.BtnMikrofon.Enable = 'off';
                drawnow;

                r  = audiorecorder(FS, 16, 1);
                recordblocking(r, SURE);
                y  = getaudiodata(r);

                app.SesVerisi = y;
                app.OrnekHizi = FS;
                app.DosyaYolu = '';
                app.LblDosyaAdi.Text = sprintf('🎙 Mikrofon kaydı (%d sn)', SURE);
                app.cizWaveform();
                app.temizleMFCC();
                app.sifirlaGosterge();
            catch ME
                uialert(app.UIFigure, sprintf('Mikrofon hatası:\n%s', ME.message), 'Hata', 'Icon','error');
            end
            app.BtnMikrofon.Text   = '🎙 Mikrofon ile Kaydet';
            app.BtnMikrofon.Enable = 'on';
        end

       
        function BtnAnalizEtCallback(app, ~)

            if ~app.ModelYuklendi
                uialert(app.UIFigure, 'Önce model yükleyin.', 'Model Gerekli', 'Icon','warning');
                return;
            end
            if isempty(app.SesVerisi)
                uialert(app.UIFigure, 'Ses dosyası seçin veya mikrofon ile kayıt alın.', 'Ses Gerekli', 'Icon','warning');
                return;
            end

            try
                app.BtnAnalizEt.Text   = '⏳ Analiz ediliyor...';
                app.BtnAnalizEt.Enable = 'off';
                drawnow;

                % Geçici dosyaya yaz (extract_features dosya yolu bekler)
                geciciDosya = fullfile(tempdir, 'duygu_gecici.wav');
                audiowrite(geciciDosya, app.SesVerisi, app.OrnekHizi);

                % Özellik çıkar (1×42)
                ozellikler = extract_features(geciciDosya);

                % Boyut uyum kontrolü
                beklenen = numel(app.Mu);
                alinan   = numel(ozellikler);
                if alinan ~= beklenen
                    error(['Özellik boyutu uyumsuz!\n' ...
                           'Model %d özellik bekliyor, extract_features %d üretiyor.\n' ...
                           'extract_features.m ve model.mat aynı versiyonda olmalı.'], ...
                           beklenen, alinan);
                end

                % Z-Score normalize
                ozNorm = (ozellikler - app.Mu) ./ app.Sigma;

                % Posterior olasılıklarla tahmin
                % [etiket, negKayip, posterior] = predict(model, X)
                % posterior: 1×K — her sınıf için olasılık
                [tahmin, negLoss, skorlar] = predict(app.Model, ozNorm);
                duyguAdi = char(tahmin);

                K = numel(app.Model.ClassNames);
                if size(skorlar, 2) == K
                    % fitPosterior uygulanmış → skorlar zaten 1×K olasılık
                    posterior = double(skorlar);
                else
                    % fitPosterior yok → NegLoss'u kullan (zaten 1×K, flip edince skor olur)
                    scores    = negLoss;
                    posterior = exp(scores) ./ sum(exp(scores));
                end
                sinifSirasi = app.Model.ClassNames;   % categorical

                % MFCC ısı haritası
                app.cizMFCC(ozellikler(1:13));

                % Duygu etiketi
                app.gosterDuygu(duyguAdi);

                % Güven çubuğu
                app.gosterGuven(sinifSirasi, posterior);

            catch ME
                uialert(app.UIFigure, sprintf('Analiz hatası:\n%s', ME.message), 'Hata', 'Icon','error');
            end

            app.BtnAnalizEt.Text   = '🔍 Analiz Et';
            app.BtnAnalizEt.Enable = 'on';
        end

    end  % callbacks

    % ==================================================================
    % YARDIMCI FONKSİYONLAR
    % ==================================================================
    methods (Access = private)

        function cizWaveform(app)
            y = app.SesVerisi; fs = app.OrnekHizi;
            t = (0:length(y)-1) / fs;
            cla(app.AxesWaveform);
            plot(app.AxesWaveform, t, y, 'Color', [0.2 0.5 0.8], 'LineWidth', 0.8);
            xlabel(app.AxesWaveform, 'Zaman (sn)', 'FontSize', 10);
            ylabel(app.AxesWaveform, 'Genlik',      'FontSize', 10);
            title(app.AxesWaveform,  'Ses Dalgası', 'FontSize', 11);
            xlim(app.AxesWaveform, [0 max(t)]);
            grid(app.AxesWaveform, 'on');
        end

        function cizMFCC(app, mfccOrt)
            cla(app.AxesMFCC);
            imagesc(app.AxesMFCC, mfccOrt);
            colormap(app.AxesMFCC, 'jet');
            colorbar(app.AxesMFCC);
            xticks(app.AxesMFCC, 1:13);
            xticklabels(app.AxesMFCC, arrayfun(@(n) sprintf('C%d',n), 1:13, 'UniformOutput', false));
            yticks(app.AxesMFCC, []);
            xlabel(app.AxesMFCC, 'MFCC Katsayısı', 'FontSize', 10);
            title(app.AxesMFCC,  'MFCC Ortalamaları', 'FontSize', 11);
        end

        function temizleMFCC(app)
            cla(app.AxesMFCC);
            title(app.AxesMFCC, 'MFCC Ortalamaları', 'FontSize', 11);
        end

        function gosterDuygu(app, duyguAdi)
            switch duyguAdi
                case 'Nötr',    emoji = '😐'; renk = [0.2 0.5 0.8];
                case 'Mutlu',   emoji = '😊'; renk = [0.1 0.7 0.2];
                case 'Üzgün',   emoji = '😢'; renk = [0.8 0.5 0.1];
                case 'Sinirli', emoji = '😠'; renk = [0.8 0.1 0.1];
                otherwise,      emoji = '❓'; renk = [0.4 0.4 0.4];
            end
            app.LblDuygu.Text      = sprintf('%s  %s', emoji, duyguAdi);
            app.LblDuygu.FontColor = renk;
        end

        % ----------------------------------------------------------
        % Güven çubuğu grafik
        % sinifSirasi : categorical array — model sınıf sırası
        % posterior   : 1×K double — her sınıfın olasılığı
        % ----------------------------------------------------------
        function gosterGuven(app, sinifSirasi, posterior)
    % sinifSirasi: model ClassNames (categorical) — posterior ile AYNI sırada
    % Doğrudan bu sırayı kullan, yeniden eşleştirme yapma (Türkçe karakter sorunu çıkar)
    
            K      = numel(sinifSirasi);
            yuzde  = posterior * 100;
            labels = cellstr(sinifSirasi);   % categorical → cell string

            cla(app.AxesGuven);
            renkMat = app.SinifRenkleri;

    % Renk sırasını model sırasına göre ayarla
            etiketRef = {'Nötr','Mutlu','Üzgün','Sinirli'};
            renkSira  = zeros(K, 3);
            for s = 1:K
                idx = find(strcmp(etiketRef, labels{s}));
                if ~isempty(idx)
                    renkSira(s,:) = renkMat(idx,:);
                else
                    renkSira(s,:) = [0.5 0.5 0.5];
                end
            end

            bh = barh(app.AxesGuven, 1:K, yuzde, 0.55);
            bh.FaceColor = 'flat';
            for s = 1:K
                bh.CData(s,:) = renkSira(s,:);
            end

            for s = 1:K
                text(app.AxesGuven, min(yuzde(s)+1, 95), s, ...
                    sprintf('%.1f%%', yuzde(s)), ...
                    'VerticalAlignment', 'middle', ...
                    'FontSize', 11, 'FontWeight', 'bold');
            end

            xlim(app.AxesGuven, [0 105]);
            yticks(app.AxesGuven, 1:K);
            yticklabels(app.AxesGuven, labels);
            app.AxesGuven.YDir = 'reverse';
            xlabel(app.AxesGuven, 'Güven (%)', 'FontSize', 10);
            title(app.AxesGuven, 'Sınıf Güven Dağılımı', 'FontSize', 11);
            grid(app.AxesGuven, 'on');
            app.AxesGuven.GridAlpha = 0.3;
        end

            

        function sifirlaGosterge(app)
            app.LblDuygu.Text      = '—';
            app.LblDuygu.FontColor = [0.4 0.4 0.4];
            cla(app.AxesGuven);
            title(app.AxesGuven, 'Sınıf Güven Dağılımı', 'FontSize', 11);
        end

        function guvenEkseniniHazirla(app)
            % Model yüklendikten sonra güven eksenini hazırla
            cla(app.AxesGuven);
            title(app.AxesGuven, 'Sınıf Güven Dağılımı', 'FontSize', 11);
            xlabel(app.AxesGuven, 'Güven (%)', 'FontSize', 10);
            yticks(app.AxesGuven, 1:numel(app.Etiketler));
            yticklabels(app.AxesGuven, app.Etiketler);
            app.AxesGuven.YDir = 'reverse';
            xlim(app.AxesGuven, [0 105]);
        end

    end  % helpers

    % ==================================================================
    % BILEŞEN OLUŞTURMA
    % ==================================================================
    methods (Access = private)

        function createComponents(app)

            % --- Ana Pencere ---
            app.UIFigure          = uifigure('Visible', 'off');
            app.UIFigure.Position = [80 80 960 780];
            app.UIFigure.Name     = 'Ses Duygu Tanıma  v2';
            app.UIFigure.Color    = [0.95 0.95 0.97];

            % ===========================================================
            % PANEL 1 — Model
            % ===========================================================
            app.PanelModel              = uipanel(app.UIFigure);
            app.PanelModel.Title        = '🧠  Model';
            app.PanelModel.Position     = [20 690 920 75];
            app.PanelModel.FontSize     = 13;
            app.PanelModel.FontWeight   = 'bold';

            app.BtnModelYukle                  = uibutton(app.PanelModel, 'push');
            app.BtnModelYukle.Text             = '📂 Modeli Yükle';
            app.BtnModelYukle.Position         = [15 12 165 38];
            app.BtnModelYukle.FontSize         = 13;
            app.BtnModelYukle.BackgroundColor  = [0.2 0.5 0.8];
            app.BtnModelYukle.FontColor        = [1 1 1];
            app.BtnModelYukle.ButtonPushedFcn  = @(~,~) app.BtnModelYukleCallback();

            app.LblModelDurum            = uilabel(app.PanelModel);
            app.LblModelDurum.Text       = '⚠  Model yüklenmedi';
            app.LblModelDurum.Position   = [195 17 500 28];
            app.LblModelDurum.FontSize   = 13;
            app.LblModelDurum.FontWeight = 'bold';
            app.LblModelDurum.FontColor  = [0.7 0.4 0.0];

            % ===========================================================
            % PANEL 2 — Ses Girişi
            % ===========================================================
            app.PanelSes            = uipanel(app.UIFigure);
            app.PanelSes.Title      = '🔊  Ses Girişi';
            app.PanelSes.Position   = [20 595 920 85];
            app.PanelSes.FontSize   = 13;
            app.PanelSes.FontWeight = 'bold';

            app.BtnDosyaSec                 = uibutton(app.PanelSes, 'push');
            app.BtnDosyaSec.Text            = '📁 Ses Dosyası Seç';
            app.BtnDosyaSec.Position        = [15 18 185 38];
            app.BtnDosyaSec.FontSize        = 12;
            app.BtnDosyaSec.BackgroundColor = [0.2 0.6 0.35];
            app.BtnDosyaSec.FontColor       = [1 1 1];
            app.BtnDosyaSec.ButtonPushedFcn = @(~,~) app.BtnDosyaSecCallback();

            app.BtnMikrofon                 = uibutton(app.PanelSes, 'push');
            app.BtnMikrofon.Text            = '🎙 Mikrofon ile Kaydet';
            app.BtnMikrofon.Position        = [215 18 210 38];
            app.BtnMikrofon.FontSize        = 12;
            app.BtnMikrofon.BackgroundColor = [0.65 0.25 0.1];
            app.BtnMikrofon.FontColor       = [1 1 1];
            app.BtnMikrofon.ButtonPushedFcn = @(~,~) app.BtnMikofonCallback();

            app.LblDosyaAdi            = uilabel(app.PanelSes);
            app.LblDosyaAdi.Text       = 'Henüz dosya seçilmedi.';
            app.LblDosyaAdi.Position   = [440 23 460 28];
            app.LblDosyaAdi.FontSize   = 11;
            app.LblDosyaAdi.FontColor  = [0.4 0.4 0.4];

            % ===========================================================
            % PANEL 3 — Sonuç
            % ===========================================================
            app.PanelSonuc            = uipanel(app.UIFigure);
            app.PanelSonuc.Title      = '📊  Sonuç';
            app.PanelSonuc.Position   = [20 20 920 535];
            app.PanelSonuc.FontSize   = 13;
            app.PanelSonuc.FontWeight = 'bold';

            % Analiz Et butonu
            app.BtnAnalizEt                 = uibutton(app.UIFigure, 'push');
            app.BtnAnalizEt.Text            = '🔍 Analiz Et';
            app.BtnAnalizEt.Position        = [20 552 160 38];
            app.BtnAnalizEt.FontSize        = 14;
            app.BtnAnalizEt.FontWeight      = 'bold';
            app.BtnAnalizEt.BackgroundColor = [0.45 0.1 0.65];
            app.BtnAnalizEt.FontColor       = [1 1 1];
            app.BtnAnalizEt.ButtonPushedFcn = @(~,~) app.BtnAnalizEtCallback();

            % Büyük duygu etiketi
            app.LblDuygu            = uilabel(app.UIFigure);
            app.LblDuygu.Text       = '—';
            app.LblDuygu.Position   = [195 548 620 52];
            app.LblDuygu.FontSize   = 30;
            app.LblDuygu.FontWeight = 'bold';
            app.LblDuygu.FontColor  = [0.4 0.4 0.4];

            % Güven dağılımı ekseni (yatay çubuk)
            app.AxesGuven          = uiaxes(app.PanelSonuc);
            app.AxesGuven.Position = [15 330 420 175];
            title(app.AxesGuven, 'Sınıf Güven Dağılımı', 'FontSize', 11);
            xlabel(app.AxesGuven, 'Güven (%)', 'FontSize', 10);
            xlim(app.AxesGuven, [0 105]);
            grid(app.AxesGuven, 'on');

            % Waveform ekseni
            app.AxesWaveform          = uiaxes(app.PanelSonuc);
            app.AxesWaveform.Position = [450 330 455 175];
            title(app.AxesWaveform, 'Ses Dalgası', 'FontSize', 11);
            xlabel(app.AxesWaveform, 'Zaman (sn)', 'FontSize', 10);
            ylabel(app.AxesWaveform, 'Genlik',      'FontSize', 10);
            grid(app.AxesWaveform, 'on');

            % MFCC ısı haritası ekseni
            app.AxesMFCC          = uiaxes(app.PanelSonuc);
            app.AxesMFCC.Position = [15 10 880 310];
            title(app.AxesMFCC, 'MFCC Ortalamaları (Isı Haritası)', 'FontSize', 11);
            xlabel(app.AxesMFCC, 'MFCC Katsayısı', 'FontSize', 10);
            grid(app.AxesMFCC, 'off');

        end

    end  % createComponents

    % ==================================================================
    % BAŞLATMA
    % ==================================================================
    methods (Access = public)

        function app = DuyguTanima()
            createComponents(app);
            registerApp(app, app.UIFigure);

            app.ModelYuklendi = false;
            app.SesVerisi     = [];
            app.OrnekHizi     = 22050;

            app.UIFigure.Visible = 'on';

            if nargout == 0, clear app; end
        end

        function delete(app)
            delete(app.UIFigure);
        end

    end

end
