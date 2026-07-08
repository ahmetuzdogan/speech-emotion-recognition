function features = extract_features(dosyaYolu)

%ses dosyasından özellik vektörü çıkarıyoruz

NUM_MFCC       = 13;
CERCEVE_SURESI = 0.025;   % 25 ms
ADIM_SURESI    = 0.010;   % 10 ms

%audio toolbox ile ses dosyası okunuyor
try
    [y, fs] = audioread(dosyaYolu);
catch ME
    error('extract_features: Dosya okunamadı — %s\nHata: %s', dosyaYolu, ME.message);
end


if size(y, 2) > 1
    y = mean(y, 2);
end


if length(y) < fs * 0.1
    warning('extract_features: Sinyal çok kısa, özellikler sıfırlanıyor.');
    features = zeros(1, NUM_MFCC * 3 + 3);
    return;
end

%!!!!!Sesi küçük 25 ms'lik pencerelere kesiyoruz. 
% Her pencereye Fourier Dönüşümü uyguluyoruz bu sesin içindeki frekansları ayırt ediyor. 

cerceveBoy = round(CERCEVE_SURESI * fs);
adimBoy    = round(ADIM_SURESI    * fs);
numCerceve = floor((length(y) - cerceveBoy) / adimBoy) + 1;
pencere    = hann(cerceveBoy);


try
    % Audio Toolbox
    [mfccMat, ~, ~] = mfcc(y, fs, ...
        'NumCoeffs',     NUM_MFCC,           ...
        'WindowLength',  cerceveBoy,         ...
        'OverlapLength', cerceveBoy - adimBoy, ...
        'LogEnergy',     'Ignore');
catch
    mfccMat = hesaplaMFCC_Manuel(y, fs, NUM_MFCC, cerceveBoy, adimBoy);
end


mfccOrt = mean(mfccMat, 1);


mfccStd = std(mfccMat, 0, 1);


if size(mfccMat, 1) >= 3
    deltaMat        = zeros(size(mfccMat));
    deltaMat(1,:)   = mfccMat(2,:)   - mfccMat(1,:);       % ilk çerçeve
    deltaMat(end,:) = mfccMat(end,:) - mfccMat(end-1,:);   % son çerçeve
    for t = 2 : size(mfccMat,1)-1
        deltaMat(t,:) = (mfccMat(t+1,:) - mfccMat(t-1,:)) / 2;
    end
    deltaMfccOrt = mean(deltaMat, 1);   % 1×13
else
    deltaMfccOrt = zeros(1, NUM_MFCC);
end


enerji = zeros(1, numCerceve);
for k = 1 : numCerceve
    bas      = (k-1)*adimBoy + 1;
    bit      = bas + cerceveBoy - 1;
    enerji(k) = mean(y(bas:bit) .^ 2);
end
enerijiOrt = mean(log(enerji + 1e-10));


zcr = zeros(1, numCerceve);
for k = 1 : numCerceve
    bas     = (k-1)*adimBoy + 1;
    bit     = bas + cerceveBoy - 1;
    seg     = y(bas:bit);
    zcr(k)  = sum(abs(diff(sign(seg)))) / (2 * cerceveBoy);
end
zcrOrt = mean(zcr);


fftBoy         = 2^nextpow2(cerceveBoy);
spektralMerkez = zeros(1, numCerceve);

for k = 1 : numCerceve
    bas     = (k-1)*adimBoy + 1;
    bit     = bas + cerceveBoy - 1;
    seg     = y(bas:bit) .* pencere;
    sp      = abs(fft(seg, fftBoy));
    sp      = sp(1:floor(fftBoy/2)+1);
    frekans = linspace(0, fs/2, length(sp))';
    topGuc  = sum(sp);
    if topGuc > 1e-10
        spektralMerkez(k) = sum(frekans .* sp) / topGuc;
    end
end
spektralMerkezOrt = mean(spektralMerkez);


features = [mfccOrt, mfccStd, deltaMfccOrt, enerijiOrt, zcrOrt, spektralMerkezOrt];

end  % extract_features



function mfccMat = hesaplaMFCC_Manuel(y, fs, numCoeffs, cerceveBoy, adimBoy)

NUM_MEL = 26;
fftBoy  = 2^nextpow2(cerceveBoy);
nC      = floor((length(y) - cerceveBoy) / adimBoy) + 1;
pencere = hann(cerceveBoy);

melMin = hz2mel(0);
melMax = hz2mel(fs/2);
melNok = linspace(melMin, melMax, NUM_MEL+2);
hzNok  = mel2hz(melNok);
binNok = round(hzNok / (fs/fftBoy));

filtreBank = zeros(NUM_MEL, floor(fftBoy/2)+1);
for m = 1:NUM_MEL
    sol = binNok(m); merk = binNok(m+1); sag = binNok(m+2);
    for k = sol:merk
        if merk > sol, filtreBank(m,k+1) = (k-sol)/(merk-sol); end
    end
    for k = merk:sag
        if sag > merk, filtreBank(m,k+1) = (sag-k)/(sag-merk); end
    end
end

mfccMat = zeros(nC, numCoeffs);
for n = 1:nC
    bas = (n-1)*adimBoy+1; bit = bas+cerceveBoy-1;
    seg = y(bas:bit) .* pencere;
    SP  = abs(fft(seg, fftBoy)).^2;
    SP  = SP(1:floor(fftBoy/2)+1);
    mel = log(filtreBank*SP + 1e-10);
    d   = dct(mel);
    mfccMat(n,:) = d(1:numCoeffs);
end
end

function mel = hz2mel(hz), mel = 2595*log10(1+hz/700); end
function hz  = mel2hz(mel), hz  = 700*(10.^(mel/2595)-1); end