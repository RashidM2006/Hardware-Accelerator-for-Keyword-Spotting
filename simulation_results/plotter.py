from matplotlib import pyplot as plt

FILE = "stdout.txt"

if __name__=="__main__":
    with open(FILE, 'r') as f:
        lines = f.readlines()
    start = lines.index("Capturing FFT output (frequency domain):\n") + 1
    end = start + lines[start:].index("\n")

    bins = []
    real = []
    imag = []
    for l in lines[start:end]:
        print(l)
        bin_start = l.index("Bin[") + 4
        bin_end = bin_start + l[bin_start:].index("]")
        bins.append(int(l[bin_start:bin_end]))

        real_start = l.index("Real=") + 5
        real_end = real_start + l[real_start:].index(" ")
        real.append(int(l[real_start:real_end], 16))

        imag_start = l.index("Imag=") + 5
        imag_end = imag_start + l[imag_start:].index(" ")
        imag.append(int(l[imag_start:imag_end], 16))

    plt.plot(bins, real, label="Real")
    plt.plot(bins, imag, label="Imag")
    plt.legend()
    plt.show()