/* Explicitly loaded diagnostic. Reads this process only; never writes its memory. */
#define _GNU_SOURCE
#include "gdextension_interface.h"
#include <dlfcn.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#if !(defined(__APPLE__) && defined(__aarch64__)) && !(defined(__linux__) && defined(__x86_64__))
#error Unsupported diagnostic architecture
#endif
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#else
#include <elf.h>
#include <link.h>
#endif

static FILE *out;
static unsigned found[3];
static const char *names[] = {"sin", "sinf", "acosf"};

static void quoted(const char *s) {
    fputc('"', out);
    for (; *s; ++s) {
        unsigned char c = (unsigned char)*s;
        if (c == '"' || c == '\\') fputc('\\', out);
        if (c < 32) fprintf(out, "\\u%04x", c); else fputc(c, out);
    }
    fputc('"', out);
}

static void hex(const void *p, size_t count) {
    const unsigned char *bytes = p;
    fputc('"', out);
    for (size_t i = 0; i < count; ++i) fprintf(out, "%02x", bytes[i]);
    fputc('"', out);
}

static void address(uintptr_t p) { fprintf(out, "\"0x%" PRIxPTR "\"", p); }

#if defined(__APPLE__)
static void image_id(const void *base) {
    const struct mach_header_64 *h = base;
    const struct load_command *c = (const void *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; ++i) {
        if (c->cmd == LC_UUID) { hex(((const struct uuid_command *)c)->uuid, 16); return; }
        c = (const void *)((const char *)c + c->cmdsize);
    }
    quoted("");
}
#else
static void image_id(const void *base) {
    const Elf64_Ehdr *h = base;
    const Elf64_Phdr *p = (const void *)((const char *)base + h->e_phoff);
    for (unsigned i = 0; i < h->e_phnum; ++i) {
        if (p[i].p_type != PT_NOTE) continue;
        const char *cursor = (const void *)((h->e_type == ET_DYN ? (uintptr_t)base : 0) + p[i].p_vaddr);
        const char *end = cursor + p[i].p_memsz;
        while (cursor + sizeof(Elf64_Nhdr) <= end) {
            const Elf64_Nhdr *n = (const void *)cursor;
            size_t ns = (n->n_namesz + 3u) & ~3u, ds = (n->n_descsz + 3u) & ~3u;
            if (cursor + sizeof(*n) + ns + ds > end) break;
            if (n->n_type == NT_GNU_BUILD_ID && n->n_namesz == 4 &&
                    memcmp(cursor + sizeof(*n), "GNU", 4) == 0) {
                hex(cursor + sizeof(*n) + ns, n->n_descsz); return;
            }
            cursor += sizeof(*n) + ns + ds;
        }
    }
    quoted("");
}
#endif

static void binding(unsigned index, const void *slot, const void *target) {
    Dl_info info;
    if (!dladdr(target, &info) || !info.dli_fbase) return;
    if (found[index]++) fputc(',', out);
    fprintf(out, "{\"symbol\":"); quoted(names[index]);
    fprintf(out, ",\"slot\":"); address((uintptr_t)slot);
    fprintf(out, ",\"target\":"); address((uintptr_t)target);
    fprintf(out, ",\"image_base\":"); address((uintptr_t)info.dli_fbase);
    fprintf(out, ",\"image_path\":"); quoted(info.dli_fname);
    fprintf(out, ",\"image_id\":"); image_id(info.dli_fbase);
    fprintf(out, ",\"dlsym_equal\":%s", dlsym(RTLD_DEFAULT, names[index]) == target ? "true" : "false");
    /* Whole reviewed small paths, including branch instructions and literal data. */
#if defined(__APPLE__) && defined(__aarch64__)
    const size_t starts[] = {0x940, 0x3158, 0xbb30};
    const size_t ends[] = {0x10c4, 0x3498, 0xbcc0};
    const size_t entries[] = {0x970, 0x3158, 0xbb30};
    uintptr_t offset = (uintptr_t)target - (uintptr_t)info.dli_fbase;
    fprintf(out, ",\"entry_offset\":%" PRIuPTR, offset);
    if (offset == entries[index]) {
        fprintf(out, ",\"code_offset\":%zu,\"code\":", starts[index]);
        hex((const char *)info.dli_fbase + starts[index], ends[index] - starts[index]);
    }
#else
    /* Unknown profiles retain a bounded executable witness, never an acceptance. */
    fprintf(out, ",\"entry_offset\":%" PRIuPTR, (uintptr_t)target - (uintptr_t)info.dli_fbase);
    fprintf(out, ",\"code_offset\":%" PRIuPTR ",\"code\":", (uintptr_t)target - (uintptr_t)info.dli_fbase);
    hex(target, 512);
#endif
    fputc('}', out);
}

#if defined(__APPLE__)
static void imports(void) {
    const struct mach_header_64 *h = (const void *)_dyld_get_image_header(0);
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    const struct symtab_command *sym = NULL;
    const struct dysymtab_command *dysym = NULL;
    uintptr_t linkedit = 0;
    const struct load_command *c = (const void *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; ++i) {
        if (c->cmd == LC_SYMTAB) sym = (const void *)c;
        if (c->cmd == LC_DYSYMTAB) dysym = (const void *)c;
        if (c->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *s = (const void *)c;
            if (!strcmp(s->segname, "__LINKEDIT")) linkedit = slide + s->vmaddr - s->fileoff;
        }
        c = (const void *)((const char *)c + c->cmdsize);
    }
    if (!sym || !dysym || !linkedit) return;
    const struct nlist_64 *symbols = (const void *)(linkedit + sym->symoff);
    const char *strings = (const void *)(linkedit + sym->stroff);
    const uint32_t *indirect = (const void *)(linkedit + dysym->indirectsymoff);
    for (unsigned wanted = 0; wanted < 3; ++wanted) {
        if (wanted) fputc(',', out);
        fputc('[', out);
        c = (const void *)(h + 1);
        for (uint32_t i = 0; i < h->ncmds; ++i) {
            if (c->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *s = (const void *)c;
                const struct section_64 *section = (const void *)(s + 1);
                for (uint32_t j = 0; j < s->nsects; ++j) {
                    unsigned type = section[j].flags & SECTION_TYPE;
                    if (type != S_LAZY_SYMBOL_POINTERS && type != S_NON_LAZY_SYMBOL_POINTERS) continue;
                    for (uint64_t k = 0; k < section[j].size / sizeof(void *); ++k) {
                        uint64_t ii = section[j].reserved1 + k;
                        if (ii >= dysym->nindirectsyms) continue;
                        uint32_t si = indirect[ii];
                        if (si >= sym->nsyms || symbols[si].n_un.n_strx >= sym->strsize) continue;
                        const char *name = strings + symbols[si].n_un.n_strx;
                        if (name[0] != '_' || strcmp(name + 1, names[wanted])) continue;
                        const void **slot = (const void **)(slide + section[j].addr + k * sizeof(void *));
                        binding(wanted, slot, *slot);
                    }
                }
            }
            c = (const void *)((const char *)c + c->cmdsize);
        }
        fputc(']', out);
    }
}
#else
static int elf_imports(struct dl_phdr_info *info, size_t size, void *data) {
    (void)size; (void)data;
    if (info->dlpi_name && info->dlpi_name[0]) return 0;
    const Elf64_Dyn *dynamic = NULL;
    for (unsigned i = 0; i < info->dlpi_phnum; ++i)
        if (info->dlpi_phdr[i].p_type == PT_DYNAMIC)
            dynamic = (const void *)(info->dlpi_addr + info->dlpi_phdr[i].p_vaddr);
    if (!dynamic) return 1;
    const Elf64_Sym *symbols = NULL;
    const char *strings = NULL;
    const Elf64_Rela *tables[2] = {NULL, NULL};
    size_t counts[2] = {0, 0};
    for (const Elf64_Dyn *d = dynamic; d->d_tag != DT_NULL; ++d) {
        switch (d->d_tag) {
            case DT_SYMTAB: symbols = (const void *)d->d_un.d_ptr; break;
            case DT_STRTAB: strings = (const void *)d->d_un.d_ptr; break;
            case DT_JMPREL: tables[0] = (const void *)d->d_un.d_ptr; break;
            case DT_RELA: tables[1] = (const void *)d->d_un.d_ptr; break;
            case DT_PLTRELSZ: counts[0] = d->d_un.d_val / sizeof(Elf64_Rela); break;
            case DT_RELASZ: counts[1] = d->d_un.d_val / sizeof(Elf64_Rela); break;
            default: break;
        }
    }
    if (!symbols || !strings) return 1;
    for (unsigned wanted = 0; wanted < 3; ++wanted) {
        if (wanted) fputc(',', out);
        fputc('[', out);
        for (unsigned table = 0; table < 2; ++table) {
            if (!tables[table]) continue;
            for (size_t j = 0; j < counts[table]; ++j) {
                const Elf64_Rela *r = &tables[table][j];
                unsigned type = ELF64_R_TYPE(r->r_info);
                if (type != R_X86_64_JUMP_SLOT && type != R_X86_64_GLOB_DAT) continue;
                if (strcmp(strings + symbols[ELF64_R_SYM(r->r_info)].st_name, names[wanted])) continue;
                const void **slot = (const void **)(info->dlpi_addr + r->r_offset);
                binding(wanted, slot, *slot);
            }
        }
        fputc(']', out);
    }
    return 1;
}
static void imports(void) { dl_iterate_phdr(elf_imports, NULL); }
#endif

static void initialize(void *data, GDExtensionInitializationLevel level) { (void)data; (void)level; }
static void deinitialize(void *data, GDExtensionInitializationLevel level) { (void)data; (void)level; }

GDExtensionBool royal_native_arithmetic_init(GDExtensionInterfaceGetProcAddress get_proc,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
    (void)library;
    init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    init->userdata = NULL; init->initialize = initialize; init->deinitialize = deinitialize;
    const char *path = getenv("ROYAL_NATIVE_CAPTURE");
    if (!path || !(out = fopen(path, "wx"))) return 0;
    GDExtensionGodotVersion version;
    GDExtensionInterfaceGetGodotVersion get_version = (GDExtensionInterfaceGetGodotVersion)get_proc("get_godot_version");
    if (!get_version) { fclose(out); return 0; }
    get_version(&version);
    Dl_info engine;
    if (!dladdr((const void *)get_proc, &engine)) { fclose(out); return 0; }
    fprintf(out, "{\"schema\":1,\"pid\":%ld,\"engine_path\":", (long)getpid()); quoted(engine.dli_fname);
    fprintf(out, ",\"engine_version\":"); quoted(version.string);
    fprintf(out, ",\"engine_version_components\":[%u,%u,%u]", version.major, version.minor, version.patch);
#if defined(__APPLE__)
    fprintf(out, ",\"platform\":\"macos-arm64\",\"engine_image_id\":");
#else
    fprintf(out, ",\"platform\":\"linux-x86_64\",\"engine_image_id\":");
#endif
    image_id(engine.dli_fbase);
    fprintf(out, ",\"imports\":["); imports();
    fprintf(out, "]}\n");
    int failed = ferror(out); if (fclose(out)) failed = 1;
    return failed ? 0 : 1;
}
