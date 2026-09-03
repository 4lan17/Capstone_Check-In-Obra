package cl.duocuc.checkinobra.importacion;

import org.apache.poi.EncryptedDocumentException;
import org.apache.poi.UnsupportedFileFormatException;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.DataFormatter;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.ss.usermodel.WorkbookFactory;

import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

/** Convierte una planilla Excel en filas de texto. */
public final class LectorPlanilla {

    /**
     * Tope de filas por archivo. No es una limitación técnica de POI: es que
     * una importación de catálogo son decenas o cientos de materiales, y un
     * archivo de cien mil filas es casi siempre el archivo equivocado. Fallar
     * temprano dice eso; procesarlo diez minutos y luego fallar, no.
     */
    public static final int MAXIMO_FILAS = 2000;

    private LectorPlanilla() {
    }

    /**
     * Lee la primera hoja, salta el encabezado y devuelve las filas con
     * contenido.
     *
     * @param columnas cuántas columnas leer de cada fila
     */
    public static List<FilaPlanilla> leer(InputStream entrada, int columnas) {
        try (Workbook libro = WorkbookFactory.create(entrada)) {
            if (libro.getNumberOfSheets() == 0) {
                throw new IllegalArgumentException("La planilla no tiene ninguna hoja");
            }
            Sheet hoja = libro.getSheetAt(0);
            DataFormatter formateador = new DataFormatter();

            List<FilaPlanilla> filas = new ArrayList<>();
            // Se parte en 1: la fila 0 es el encabezado de la plantilla.
            for (int i = 1; i <= hoja.getLastRowNum(); i++) {
                Row fila = hoja.getRow(i);
                List<String> celdas = new ArrayList<>(columnas);
                for (int c = 0; c < columnas; c++) {
                    Cell celda = fila == null ? null : fila.getCell(c);
                    celdas.add(celda == null ? "" : formateador.formatCellValue(celda).trim());
                }
                FilaPlanilla leida = new FilaPlanilla(i + 1, celdas);
                if (!leida.vacia()) {
                    filas.add(leida);
                }
                if (filas.size() > MAXIMO_FILAS) {
                    throw new IllegalArgumentException(
                            "La planilla supera las " + MAXIMO_FILAS + " filas. Divídela en varios archivos.");
                }
            }
            return filas;
        } catch (IOException | EncryptedDocumentException | UnsupportedFileFormatException e) {
            // El caso frecuente es un .csv o un .xls renombrado a .xlsx, o un
            // archivo con contraseña. Decirlo así ahorra la ronda de "no
            // funciona" — el stack trace de POI no le sirve a un administrador.
            //
            // `UnsupportedFileFormatException` va explícita aunque herede de
            // IllegalArgumentException: sin capturarla, el que llega a la app
            // es el mensaje de POI en inglés ("Your InputStream was neither an
            // OLE2 stream, nor an OOXML stream"), que no le dice nada a quien
            // subió el archivo equivocado.
            throw new IllegalArgumentException(
                    "No se pudo leer la planilla. Debe ser un archivo Excel (.xlsx o .xls) sin contraseña.");
        }
    }
}
